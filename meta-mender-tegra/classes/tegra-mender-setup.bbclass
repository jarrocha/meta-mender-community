inherit l4t_bsp

python () {
    # insert l4t-mender-<version> as a machine-specific override for tegra platforms
    machine_overrides = d.getVar('MACHINEOVERRIDES', False).split(':')
    try:
        i = machine_overrides.index('tegra')
        l4t_ver = 'l4t-mender-%s' % d.getVar('L4T_VERSION').replace('.','-')
        d.setVar('MACHINEOVERRIDES', ':'.join(machine_overrides[:i] + [l4t_ver] + machine_overrides[i:]))
    except ValueError:
        pass
}

def tegra_mender_set_rootfs_partsize(calc_rootfs_size_kb):
    return calc_rootfs_size_kb * 1024

def tegra_mender_image_rootfs_size(d):
    rootfspart_size = d.getVar('ROOTFSPART_SIZE')
    if rootfspart_size:
        calc_rootfs_size = int(rootfspart_size) // 1024
    else:
        calc_rootfs_size = int(d.getVar('MENDER_CALC_ROOTFS_SIZE'))
    calc_rootfs_size = (calc_rootfs_size * 95) // 100
    return calc_rootfs_size - eval(d.getVar('IMAGE_ROOTFS_EXTRA_SPACE'))

# meta-tegra and tegraflash requirements
IMAGE_CLASSES += "image_types_mender_tegra"
IMAGE_FSTYPES += "tegraflash"

ARTIFACTIMG_FSTYPE = "ext4"
# Generate dataimg for use with tegraflash
IMAGE_TYPEDEP_tegraflash += " dataimg"
IMAGE_FSTYPES += "dataimg"
PREFERRED_PROVIDER_u-boot-fw-utils = "u-boot-fw-utils-tegra"
PREFERRED_PROVIDER_libubootenv_tegra = "${@'libubootenv-fake' if d.getVar('PREFERRED_PROVIDER_virtual/bootloader').startswith('cboot') else 'libubootenv'}"
PREFERRED_RPROVIDER_u-boot-fw-utils = "u-boot-fw-utils-tegra"
PREFERRED_RPROVIDER_libubootenv-bin_tegra = "${@'libubootenv-fake' if d.getVar('PREFERRED_PROVIDER_virtual/bootloader').startswith('cboot') else 'libubootenv-bin'}"
# Note: this isn't really a boot file, just put it here to keep the mender build from
# complaining about empty IMAGE_BOOT_FILES.  We won't use the full image anyway, just the mender file
IMAGE_BOOT_FILES = "u-boot-dtb.bin"
# Mender customizations to support jetson platforms.  This needs to
# match up with your defined flash or sdcard layout.
# You will need to update these partition values when you update the flash layout.  One way to find the correct number is to
# boot into an emergency shell and examine the /dev/mmcblk* devices,
# or use the uboot console to look at mtdparts
MENDER_DATA_PART_NUMBER_DEFAULT_tegra186 = "34"
MENDER_DATA_PART_NUMBER_DEFAULT_tegra194 = "43"
MENDER_DATA_PART_NUMBER_DEFAULT_tegra210 = "${@'16' if (d.getVar('TEGRA_SPIFLASH_BOOT') or '') == '1' else '23'}"
MENDER_DATA_PART_NUMBER_DEFAULT_jetson-nano-emmc = "19"
MENDER_DATA_PART_NUMBER_DEFAULT_xavier-nx = "12"
MENDER_ROOTFS_PART_A_NUMBER_DEFAULT = "1"
MENDER_ROOTFS_PART_B_NUMBER_DEFAULT_tegra186 = "33"
MENDER_ROOTFS_PART_B_NUMBER_DEFAULT_tegra194 = "42"
MENDER_ROOTFS_PART_B_NUMBER_DEFAULT_tegra210 = "${@'15' if (d.getVar('TEGRA_SPIFLASH_BOOT') or '') == '1' else '22'}"
MENDER_ROOTFS_PART_B_NUMBER_DEFAULT_jetson-nano-emmc = "18"
MENDER_ROOTFS_PART_B_NUMBER_DEFAULT_xavier-nx = "11"

# Machine name and flash layout changed for SDcard Nanos in L4T R32.5.x
MENDER_DATA_PART_NUMBER_DEFAULT_jetson-nano-devkit = "3"
MENDER_ROOTFS_PART_B_NUMBER_DEFAULT_jetson-nano-devkit = "2"
# Machine name changed for Nano-eMMC in L4T R32.5.x
MENDER_DATA_PART_NUMBER_DEFAULT_jetson-nano-devkit-emmc = "19"
MENDER_ROOTFS_PART_B_NUMBER_DEFAULT_jetson-nano-devkit-emmc = "18"
# Added in L4T R32.5.x
MENDER_DATA_PART_NUMBER_DEFAULT_jetson-nano-2gb-devkit = "4"
MENDER_ROOTFS_PART_B_NUMBER_DEFAULT_jetson-nano-2gb-devkit = "2"

# Use a 4096 byte alignment for support of tegraflash scheme and default partition locations
MENDER_PARTITION_ALIGNMENT = "4096"

MENDER_RESERVED_SPACE_BOOTLOADER_DATA = "0"

# See note in https://docs.mender.io/1.7/troubleshooting/running-yocto-project-image#i-moved-from-an-older-meta-mender-branch-to-the-thud-branch-and
# Prevents build failure during mkfs.ext4 step on warrior
MENDER_PARTITIONING_OVERHEAD_KB = "0"
# We don't use a boot partition in the mender image, we use tegraflash to setup our boot partition
MENDER_BOOT_PART = ""
MENDER_BOOT_PART_SIZE_MB = "0"

# Calculate the ROOTFSPART_SIZE value based on the *calculated*
# IMAGE_ROOTFS_SIZE set by mender. Do *not* use ${IMAGE_ROOTFS_SIZE}
# here; when we're called on in the context of an initramfs image
# build (for BUP payload generation), its size is set smaller than
# the actual rootfs image, so the resulting flash layout XML files
# will be different between the two contexts, leading to boot
# failures after bootloader updates.
ROOTFSPART_SIZE = "${@tegra_mender_set_rootfs_partsize(${MENDER_CALC_ROOTFS_SIZE})}"

# See https://hub.mender.io/t/yocto-thud-release-and-mender/144
# Default for thud and later is grub integration but we need to use u-boot integration already included.
# Leave out sdimg since we don't use this with tegra (instead use
# tegraflash)
MENDER_FEATURES_ENABLE_append_tegra = "${@tegra_mender_uboot_feature(d)}"
MENDER_FEATURES_DISABLE_append_tegra = " mender-grub mender-image-uefi"

# Use these variables to adjust your total rootfs size across both
# images. Rootfs size will be approximately 1/2 of
# MENDER_STORAGE_TOTAL_SIZE_MB (ignoring alignment).
# Calculate the total size based on the eMMC or SDcard size configured
# for the machine, subtracting off space for the boot-related files
# and other NVIDIA-specific partitions (by default, 1GiB).
def tegra_mender_calc_total_size(d):
    # For pre-production Nanos, use SDCard size, which in the machine
    # config ends with a size factor (K, M, or G). Note that the
    # factors are kilo/mega/giga, rather than kibi/mibi/gibi.
    if (d.getVar('TEGRA_SPIFLASH_BOOT') or '') == '1':
        sdcard_size = d.getVar('TEGRAFLASH_SDCARD_SIZE')
        fchar = sdcard_size[-1:].upper()
        sdcard_size = int(sdcard_size[:-1])
        if fchar == 'G':
            total_size_bytes = sdcard_size * 1000 * 1000 * 1000
        elif fchar == 'K':
            total_size_bytes = sdcard_size * 1000
        elif fchar == 'M':
            total_size_bytes = sdcard_size * 1000 * 1000
        else:
            bb.error('TEGRAFLASH_SDCARD_SIZE does not end with G, K, or M')
    else:
        total_size_bytes = int(d.getVar('EMMC_SIZE'))
    # Mender uses mibibytes, not megabytes
    return total_size_bytes // (1024*1024) - int(d.getVar('TEGRA_MENDER_RESERVED_SPACE_MB'))

MENDER_IMAGE_ROOTFS_SIZE_DEFAULT = "${@tegra_mender_image_rootfs_size(d)}"
TEGRA_MENDER_RESERVED_SPACE_MB_DEFAULT = "1024"
TEGRA_MENDER_RESERVED_SPACE_MB_DEFAULT_jetson-nano-2gb-devkit = "5120"
TEGRA_MENDER_RESERVED_SPACE_MB ?= "${TEGRA_MENDER_RESERVED_SPACE_MB_DEFAULT}"
MENDER_STORAGE_TOTAL_SIZE_MB_DEFAULT_tegra = "${@tegra_mender_calc_total_size(d)}"

def tegra_mender_uboot_feature(d):
    if (d.getVar('PREFERRED_PROVIDER_virtual/bootloader') or '').startswith('cboot'):
        return " mender-persist-systemd-machine-id"
    return " mender-uboot mender-persist-systemd-machine-id"

_MENDER_IMAGE_DEPS_EXTRA = ""
_MENDER_IMAGE_DEPS_EXTRA_tegra = "tegra-state-scripts:do_deploy"
do_image_mender[depends] += "${_MENDER_IMAGE_DEPS_EXTRA}"

# mender-setup-image adds kernel-image and kernel-devicetree
# to MACHINE_ESSENTIAL_EXTRA_RDEPENDS, but they should *not*
# be included by default on cboot platforms.
MACHINE_ESSENTIAL_EXTRA_RDEPENDS_remove_tegra194 = "kernel-image kernel-devicetree"
MACHINE_ESSENTIAL_EXTRA_RDEPENDS_remove_tegra186 = "${@'kernel-image kernel-devicetree' if (d.getVar('PREFERRED_PROVIDER_virtual/bootloader') or '').startswith('cboot') else ''}"

# Compatibility settings for handling the machine name changes
# made in L4T R32.5.x, to allow for upgrades.  This does not
# include jetson-nano-qspi-sd (now jetson-nano-devkit) due to
# major changes in the flash layout.
MENDER_DEVICE_TYPES_COMPATIBLE_append_jetson-tx1-devkit = " jetson-tx1"
MENDER_DEVICE_TYPES_COMPATIBLE_append_jetson-tx2-devkit = " jetson-tx2"
MENDER_DEVICE_TYPES_COMPATIBLE_append_jetson-tx2-devkit-tx2i = " jetson-tx2i"
MENDER_DEVICE_TYPES_COMPATIBLE_append_jetson-tx2-devkit-4gb = " jetson-tx2-4gb"
MENDER_DEVICE_TYPES_COMPATIBLE_append_jetson-agx-xavier-devkit = " jetson-xavier"
MENDER_DEVICE_TYPES_COMPATIBLE_append_jetson-agx-xavier-devkit-8gb = " jetson-xavier-8gb"
MENDER_DEVICE_TYPES_COMPATIBLE_append_jetson-nano-devkit-emmc = " jetson-nano-emmc"
