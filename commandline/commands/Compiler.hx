package commands;

class Compiler {
	public static function test(args:Array<String>) {
		__build(args, ["test", getBuildTarget(), "-DTEST_BUILD"]);
	}
	public static function build(args:Array<String>) {
		__build(args, ["build", getBuildTarget(), "-DTEST_BUILD"]);
	}
	public static function release(args:Array<String>) {
		__build(args, ["build", getBuildTarget()]);
	}
	public static function testRelease(args:Array<String>) {
		__build(args, ["test", getBuildTarget()]);
	}

	private static function __build(args:Array<String>, arg:Array<String>) {
		arg.insert(0, "lime");
		arg.insert(0, "run");
		for(a in args)
			arg.push(a);
		Sys.println("Running: " + "haxelib " + arg.join(" "));
		Sys.command("haxelib", arg);
	}

	public static function getBuildTarget() {
		return switch(Sys.systemName()) {
			case "Windows": "windows";
			case "Mac": "macos";
			case "Linux": "linux";
			case def: def.toLowerCase();
		}
	}
}