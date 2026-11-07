// SPDX-License-Identifier: GPL-2.0
/*
 * hwmon bridge for the Akali360 EC fan.
 *
 * The 2021 nami EC accepts PWM_SET_FAN_TARGET_RPM and THERMAL_AUTO_FAN_CTRL
 * version 0, but not the duty/auto commands cros_ec_hwmon needs before it
 * creates pwm attributes. This module publishes one standard hwmon device so
 * CoolerControl and other hwmon clients can read the fan and set it.
 */

#include <linux/device.h>
#include <linux/hwmon.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>
#include <linux/platform_data/cros_ec_commands.h>
#include <linux/platform_data/cros_ec_proto.h>
#include <linux/units.h>

#define RPM_MIN 2700
#define RPM_MAX 5500

struct akali_fan {
	struct cros_ec_device *ec;
	struct mutex lock;
	bool manual;
	u8 pwm;
};

static struct akali_fan *akali_fan_get(struct device *dev)
{
	return dev_get_drvdata(dev);
}

static int ec_set_rpm(struct cros_ec_device *ec, u32 rpm)
{
	return cros_ec_cmd(ec, 0, EC_CMD_PWM_SET_FAN_TARGET_RPM, &rpm,
			   sizeof(rpm), NULL, 0);
}

static int ec_set_auto(struct cros_ec_device *ec)
{
	return cros_ec_cmd(ec, 0, EC_CMD_THERMAL_AUTO_FAN_CTRL, NULL, 0, NULL,
			   0);
}

static u32 pwm_to_rpm(u8 pwm)
{
	if (pwm == 0)
		return 0;
	return RPM_MIN + (pwm - 1) * (RPM_MAX - RPM_MIN) / 254;
}

static u8 rpm_to_pwm(u32 rpm)
{
	if (rpm == 0)
		return 0;
	if (rpm <= RPM_MIN)
		return 1;
	if (rpm >= RPM_MAX)
		return 255;
	return 1 + (rpm - RPM_MIN) * 254 / (RPM_MAX - RPM_MIN);
}

static int read_rpm(struct cros_ec_device *ec, long *val)
{
	__le16 speed;
	u16 rpm;
	int ret;

	ret = cros_ec_cmd_readmem(ec, EC_MEMMAP_FAN, sizeof(speed), &speed);
	if (ret < 0)
		return ret;
	rpm = le16_to_cpu(speed);
	if (rpm == EC_FAN_SPEED_NOT_PRESENT || rpm == EC_FAN_SPEED_STALLED)
		return -ENODATA;
	*val = rpm;
	return 0;
}

static bool temp_is_error(u8 temp)
{
	return temp == EC_TEMP_SENSOR_NOT_PRESENT ||
	       temp == EC_TEMP_SENSOR_ERROR ||
	       temp == EC_TEMP_SENSOR_NOT_POWERED ||
	       temp == EC_TEMP_SENSOR_NOT_CALIBRATED;
}

static int read_temp(struct cros_ec_device *ec, int channel, long *val)
{
	u8 temp;
	int ret;

	ret = cros_ec_cmd_readmem(ec, EC_MEMMAP_TEMP_SENSOR + channel, 1,
				  &temp);
	if (ret < 0)
		return ret;
	if (temp_is_error(temp))
		return -ENODATA;
	*val = kelvin_to_millicelsius((long)temp + EC_TEMP_SENSOR_OFFSET);
	return 0;
}

static const char * const temp_labels[] = {
	"F75303_Local",
	"F75303_Remote1",
	"F75303_Remote2",
};

static int akali_fan_read(struct device *dev, enum hwmon_sensor_types type,
			  u32 attr, int channel, long *val)
{
	struct akali_fan *fan = akali_fan_get(dev);
	int ret = 0;

	mutex_lock(&fan->lock);
	if (type == hwmon_fan) {
		if (attr == hwmon_fan_input)
			ret = read_rpm(fan->ec, val);
		else if (attr == hwmon_fan_min)
			*val = RPM_MIN;
		else if (attr == hwmon_fan_max)
			*val = RPM_MAX;
		else
			ret = -EOPNOTSUPP;
	} else if (type == hwmon_pwm) {
		if (attr == hwmon_pwm_enable) {
			*val = fan->manual ? 1 : 2;
		} else if (attr == hwmon_pwm_input) {
			if (fan->manual) {
				*val = fan->pwm;
			} else {
				long rpm;

				ret = read_rpm(fan->ec, &rpm);
				if (!ret)
					*val = rpm_to_pwm(rpm);
			}
		} else {
			ret = -EOPNOTSUPP;
		}
	} else if (type == hwmon_temp && attr == hwmon_temp_input) {
		ret = read_temp(fan->ec, channel, val);
	} else {
		ret = -EOPNOTSUPP;
	}
	mutex_unlock(&fan->lock);
	return ret;
}

static int akali_fan_read_string(struct device *dev,
				 enum hwmon_sensor_types type, u32 attr,
				 int channel, const char **str)
{
	if (type == hwmon_temp && attr == hwmon_temp_label &&
	    channel >= 0 && channel < 3) {
		*str = temp_labels[channel];
		return 0;
	}
	return -EOPNOTSUPP;
}

static int akali_fan_write(struct device *dev, enum hwmon_sensor_types type,
			   u32 attr, int channel, long val)
{
	struct akali_fan *fan = akali_fan_get(dev);

	(void)channel;
	int ret = -EOPNOTSUPP;

	if (type != hwmon_pwm)
		return -EOPNOTSUPP;

	mutex_lock(&fan->lock);
	if (attr == hwmon_pwm_enable) {
		if (val == 2) {
			ret = ec_set_auto(fan->ec);
			if (!ret)
				fan->manual = false;
		} else if (val == 1) {
			long rpm = 0;

			if (!fan->manual) {
				if (read_rpm(fan->ec, &rpm))
					rpm = 0;
				fan->pwm = rpm_to_pwm(rpm < 0 ? 0 : rpm);
			}
			ret = ec_set_rpm(fan->ec, pwm_to_rpm(fan->pwm));
			if (!ret)
				fan->manual = true;
		} else {
			ret = -EINVAL;
		}
	} else if (attr == hwmon_pwm_input) {
		if (val < 0 || val > 255) {
			ret = -EINVAL;
		} else {
			fan->pwm = val;
			ret = ec_set_rpm(fan->ec, pwm_to_rpm(fan->pwm));
			if (!ret)
				fan->manual = true;
		}
	}
	mutex_unlock(&fan->lock);
	return ret;
}

static umode_t akali_fan_is_visible(const void *data,
				    enum hwmon_sensor_types type, u32 attr,
				    int channel)
{
	if (type == hwmon_fan &&
	    (attr == hwmon_fan_input || attr == hwmon_fan_min ||
	     attr == hwmon_fan_max))
		return 0444;
	if (type == hwmon_pwm &&
	    (attr == hwmon_pwm_input || attr == hwmon_pwm_enable))
		return 0644;
	if (type == hwmon_temp && channel < 3 &&
	    (attr == hwmon_temp_input || attr == hwmon_temp_label))
		return 0444;
	return 0;
}

static const struct hwmon_channel_info * const akali_fan_info[] = {
	HWMON_CHANNEL_INFO(fan, HWMON_F_INPUT | HWMON_F_MIN | HWMON_F_MAX),
	HWMON_CHANNEL_INFO(pwm, HWMON_PWM_INPUT | HWMON_PWM_ENABLE),
	HWMON_CHANNEL_INFO(temp,
			   HWMON_T_INPUT | HWMON_T_LABEL,
			   HWMON_T_INPUT | HWMON_T_LABEL,
			   HWMON_T_INPUT | HWMON_T_LABEL),
	NULL
};

static const struct hwmon_ops akali_fan_ops = {
	.is_visible = akali_fan_is_visible,
	.read = akali_fan_read,
	.read_string = akali_fan_read_string,
	.write = akali_fan_write,
};

static const struct hwmon_chip_info akali_fan_chip = {
	.ops = &akali_fan_ops,
	.info = akali_fan_info,
};

static struct akali_fan akali_fan_data;

static int akali_fan_probe(struct platform_device *pdev)
{
	struct akali_fan *fan = &akali_fan_data;
	struct device *hwmon;

	mutex_init(&fan->lock);
	platform_set_drvdata(pdev, fan);
	hwmon = devm_hwmon_device_register_with_info(&pdev->dev, "akali_fan",
						     fan, &akali_fan_chip,
						     NULL);
	return PTR_ERR_OR_ZERO(hwmon);
}

static int akali_fan_suspend(struct device *dev)
{
	struct akali_fan *fan = dev_get_drvdata(dev);

	if (!fan->manual)
		return 0;
	return ec_set_auto(fan->ec);
}

static int akali_fan_resume(struct device *dev)
{
	struct akali_fan *fan = dev_get_drvdata(dev);

	if (!fan->manual)
		return 0;
	return ec_set_rpm(fan->ec, pwm_to_rpm(fan->pwm));
}

static const struct dev_pm_ops akali_fan_pm = {
	.suspend = akali_fan_suspend,
	.resume = akali_fan_resume,
};

static struct platform_driver akali_fan_driver = {
	.probe = akali_fan_probe,
	.driver = {
		.name = "akali-fan",
		.pm = &akali_fan_pm,
	},
};

static struct platform_device *akali_fan_dev;

static int match_lpcs(struct device *dev, const void *data)
{
	return dev->driver && !strcmp(dev->driver->name, "cros_ec_lpcs");
}

static void akali_fan_restore(void)
{
	if (akali_fan_data.manual && akali_fan_data.ec)
		ec_set_auto(akali_fan_data.ec);
}

static int __init akali_fan_init(void)
{
	struct device *dev;
	int ret;

	dev = bus_find_device(&platform_bus_type, NULL, NULL, match_lpcs);
	if (!dev)
		return -ENODEV;
	akali_fan_data.ec = platform_get_drvdata(to_platform_device(dev));
	put_device(dev);
	if (!akali_fan_data.ec)
		return -ENODEV;

	ret = platform_driver_register(&akali_fan_driver);
	if (ret)
		return ret;

	akali_fan_dev = platform_device_register_simple("akali-fan",
							 PLATFORM_DEVID_NONE,
							 NULL, 0);
	if (IS_ERR(akali_fan_dev)) {
		ret = PTR_ERR(akali_fan_dev);
		platform_driver_unregister(&akali_fan_driver);
		return ret;
	}
	return 0;
}

static void __exit akali_fan_exit(void)
{
	akali_fan_restore();
	platform_device_unregister(akali_fan_dev);
	platform_driver_unregister(&akali_fan_driver);
}

module_init(akali_fan_init);
module_exit(akali_fan_exit);

MODULE_DESCRIPTION("Akali360 EC fan hwmon bridge");
MODULE_LICENSE("GPL");
