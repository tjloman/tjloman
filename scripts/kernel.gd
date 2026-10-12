class_name Kernel
extends RefCounted
## THE LAND KERNEL, from GDScript's side of the door.
##
## The questions every walker, beast and builder asks of the ground — how high
## is it here, what is this chunk's grid of heights, how high is it as it is
## drawn, which way round the trees — answered in C++ (native/src/land_kernel.*,
## built into the same library as the baked shadows). Each was a few
## microseconds of interpreter, asked thousands of times a second.
##
## NOTHING HERE IS REQUIRED. Like Shade, this NEVER NAMES the native class — it
## is made through ClassDB by name — so on a machine where the library has not
## been built `land()` is null and every caller asks its GDScript twin instead,
## which is the same arithmetic, line for line. tools/live/kernel_live.gd holds
## the two to the same answers.
##
## `--no-kernel` after `--` on the command line leaves it off, so the two can be
## measured against each other in the same build.

static var _land: Object = null
static var _asked := false


## The kernel, or null when the library is not there (or was told not to be).
static func land() -> Object:
	if not _asked:
		_asked = true
		if ClassDB.class_exists(&"LandKernel") \
				and not OS.get_cmdline_user_args().has("--no-kernel"):
			_land = ClassDB.instantiate(&"LandKernel")
	return _land


## Is it on? For the meter and the tests.
static func on() -> bool:
	return land() != null
