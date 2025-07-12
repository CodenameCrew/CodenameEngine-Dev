package funkin.backend.system.modules;

import flixel.FlxState;
import flixel.sound.FlxSound;
import funkin.backend.utils.NativeAPI;
import lime.media.AudioManager;
import lime.media.AudioSource;
import haxe.Timer;

/**
 * if you are stealing this keep this comment at least please lol
 *
 * hi gray itsa me yoshicrafter29 i fixed it hehe
 */
@:dox(hide)
class AudioSwitchFix {
	public static function onAudioDisconnected() @:privateAccess {
		var soundList:Array<FlxSound> = [FlxG.sound.music];
		for (sound in FlxG.sound.list) if (sound.playing) soundList.push(sound);
		for (source in AudioSource.activeSources) source.dispose();

		AudioManager.shutdown();

		AudioManager.init();
		Main.changeID++;
		// #if !lime_doc_gen
		// if (AudioManager.context.type == OPENAL)
		// {
		// 	var alc = AudioManager.context.openal;

		// 	var device = alc.openDevice();
		// 	var ctx = alc.createContext(device);
		// 	alc.makeContextCurrent(ctx);
		// 	alc.processContext(ctx);
		// }
		// #end

		for (sound in soundList) {
			sound._paused = true;
			sound.resume();
		}

		Main.audioDisconnected = false;
	}

	private static var timer:Timer;

	private static function onRun() if (Main.audioDisconnected) onAudioDisconnected();
	public static function init() {
		NativeAPI.registerAudio();
		if (timer == null) (timer = new Timer(1000)).run = onRun;
	}
}