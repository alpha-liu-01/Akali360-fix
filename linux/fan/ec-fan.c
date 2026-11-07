#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

struct cros_ec_command {
	uint32_t version;
	uint32_t command;
	uint32_t outsize;
	uint32_t insize;
	uint32_t result;
	uint8_t data[];
};

#define CROS_EC_DEV_IOC 0xEC
#define CROS_EC_DEV_IOCXCMD _IOWR(CROS_EC_DEV_IOC, 0, struct cros_ec_command)

#define EC_CMD_GET_CMD_VERSIONS 0x0008
#define EC_CMD_PWM_GET_FAN_TARGET_RPM 0x0020
#define EC_CMD_PWM_SET_FAN_TARGET_RPM 0x0021
#define EC_CMD_PWM_SET_FAN_DUTY 0x0024
#define EC_CMD_PWM_GET_FAN_DUTY 0x0027
#define EC_CMD_THERMAL_AUTO_FAN_CTRL 0x0052

#define RPM_MIN 2700
#define RPM_MAX 5500

static int ec_fd = -1;

static int ec_command(uint32_t version, uint32_t cmd, const void *out,
		      uint32_t outsize, void *in, uint32_t insize)
{
	struct cros_ec_command *msg;
	uint32_t bytes = outsize > insize ? outsize : insize;
	int ret;

	msg = calloc(1, sizeof(*msg) + bytes);
	if (!msg)
		return -1;
	msg->version = version;
	msg->command = cmd;
	msg->outsize = outsize;
	msg->insize = insize;
	if (out && outsize)
		memcpy(msg->data, out, outsize);
	ret = ioctl(ec_fd, CROS_EC_DEV_IOCXCMD, msg);
	if (ret < 0) {
		free(msg);
		return -1;
	}
	if (msg->result != 0) {
		fprintf(stderr, "EC command 0x%x version %u result %u\n", cmd,
			version, msg->result);
		free(msg);
		return -1;
	}
	if (in && ret > 0) {
		if ((uint32_t)ret > insize)
			ret = insize;
		memcpy(in, msg->data, ret);
	}
	free(msg);
	return 0;
}

static int version_mask(uint16_t cmd, uint32_t *mask)
{
	struct {
		uint16_t cmd;
	} req = {cmd};
	struct {
		uint32_t version_mask;
	} resp;

	if (ec_command(1, EC_CMD_GET_CMD_VERSIONS, &req, sizeof(req), &resp,
		       sizeof(resp)) < 0)
		return -1;
	*mask = resp.version_mask;
	return 0;
}

static int read_sysfs_rpm(int *rpm)
{
	char name[64];
	char path[160];
	int i;

	for (i = 0; i < 8; i++) {
		FILE *f;
		snprintf(path, sizeof(path), "/sys/class/hwmon/hwmon%d/name", i);
		f = fopen(path, "r");
		if (!f)
			continue;
		if (!fgets(name, sizeof(name), f)) {
			fclose(f);
			continue;
		}
		fclose(f);
		if (strncmp(name, "cros_ec", 7) != 0)
			continue;
		snprintf(path, sizeof(path),
			 "/sys/class/hwmon/hwmon%d/fan1_input", i);
		f = fopen(path, "r");
		if (!f)
			return -1;
		if (fscanf(f, "%d", rpm) != 1) {
			fclose(f);
			return -1;
		}
		fclose(f);
		return 0;
	}
	return -1;
}

static int get_target(uint32_t *rpm)
{
	return ec_command(0, EC_CMD_PWM_GET_FAN_TARGET_RPM, NULL, 0, rpm,
			  sizeof(*rpm));
}

static int set_target(uint32_t rpm)
{
	return ec_command(0, EC_CMD_PWM_SET_FAN_TARGET_RPM, &rpm, sizeof(rpm),
			  NULL, 0);
}

static int set_auto(void)
{
	return ec_command(0, EC_CMD_THERMAL_AUTO_FAN_CTRL, NULL, 0, NULL, 0);
}

static void print_mask(const char *name, uint16_t cmd)
{
	uint32_t mask;

	if (version_mask(cmd, &mask) < 0)
		printf("%s 0x%04x  unavailable\n", name, cmd);
	else
		printf("%s 0x%04x  version_mask=0x%x\n", name, cmd, mask);
}

static int cmd_status(void)
{
	uint32_t target = 0;
	int actual = -1;

	print_mask("GET_FAN_TARGET_RPM", EC_CMD_PWM_GET_FAN_TARGET_RPM);
	print_mask("SET_FAN_TARGET_RPM", EC_CMD_PWM_SET_FAN_TARGET_RPM);
	print_mask("SET_FAN_DUTY", EC_CMD_PWM_SET_FAN_DUTY);
	print_mask("GET_FAN_DUTY", EC_CMD_PWM_GET_FAN_DUTY);
	print_mask("THERMAL_AUTO_FAN_CTRL", EC_CMD_THERMAL_AUTO_FAN_CTRL);
	if (get_target(&target) == 0)
		printf("target_rpm=%u\n", target);
	if (read_sysfs_rpm(&actual) == 0)
		printf("actual_rpm=%d\n", actual);
	return 0;
}

static int cmd_set(uint32_t rpm)
{
	if (rpm != 0 && (rpm < RPM_MIN || rpm > RPM_MAX)) {
		fprintf(stderr, "rpm must be 0 or %d-%d\n", RPM_MIN, RPM_MAX);
		return 1;
	}
	if (set_target(rpm) < 0) {
		perror("set target");
		return 1;
	}
	printf("manual target_rpm=%u\n", rpm);
	printf("thermal curve is off until: ec-fan auto\n");
	return 0;
}

static void usage(void)
{
	fprintf(stderr,
		"usage: ec-fan status\n"
		"       ec-fan set <rpm>   # 0 stops, else %d-%d\n"
		"       ec-fan auto        # restore the EC curve\n",
		RPM_MIN, RPM_MAX);
}

int main(int argc, char **argv)
{
	ec_fd = open("/dev/cros_ec", O_RDWR);
	if (ec_fd < 0) {
		perror("/dev/cros_ec");
		return 1;
	}
	if (argc == 2 && strcmp(argv[1], "status") == 0)
		return cmd_status();
	if (argc == 2 && strcmp(argv[1], "auto") == 0) {
		if (set_auto() < 0) {
			perror("auto");
			return 1;
		}
		printf("thermal curve restored\n");
		return 0;
	}
	if (argc == 3 && strcmp(argv[1], "set") == 0)
		return cmd_set((uint32_t)strtoul(argv[2], NULL, 10));
	usage();
	return 1;
}
