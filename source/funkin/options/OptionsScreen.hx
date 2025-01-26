package funkin.options;

import funkin.options.type.OptionType;

class OptionsScreen extends FlxTypedSpriteGroup<OptionType> {
	public static var optionsHeight:Float = 120;

	public var parent:OptionsTree;

	public var curSelected:Int = 0;
	public var id:Int = 0;

	private var __firstFrame:Bool = true;

	public var name:String;
	public var desc:String;
	/**
	 * The prefix to add to the translations ids.
	**/
	public var prefix:String = "";

	private var rawName(default, set):String;
	private var rawDesc(default, set):String;

	public inline function getNameID(name):String {
		return prefix + name + "-name";
	}
	public inline function getDescID(name):String {
		return prefix + name + "-desc";
	}

	public function getName(name:String, ?args:Array<Dynamic>):String {
		return TU.translate(getNameID(name), args);
	}
	public function getDesc(name:String, ?args:Array<Dynamic>):String {
		return TU.translate(getDescID(name), args);
	}
	public function translate(name:String, ?args:Array<Dynamic>):String {
		return TU.translate(prefix + name, args);
	}

	public function new(name:String, desc:String, ?prefix:String, ?options:Array<OptionType>) {
		super();
		rawName = name;
		rawDesc = desc;
		this.prefix = prefix != null ? prefix : "";
		if (options != null) for(o in options) add(o);
	}

	function set_rawName(v:String) {
		rawName = v;
		this.name = TU.exists(rawName) ? TU.translate(rawName) : rawName;
		return v;
	}

	function set_rawDesc(v:String) {
		rawDesc = v;
		this.desc = TU.exists(rawDesc) ? TU.translate(rawDesc) : rawDesc;
		return v;
	}

	public function reloadStrings() {
		this.rawName = rawName;
		this.rawDesc = rawDesc;

		for(o in members) {
			o.reloadStrings();
		}
	}

	public override function update(elapsed:Float) {
		super.update(elapsed);

		var controls = PlayerSettings.solo.controls;

		changeSelection((controls.UP_P ? -1 : 0) + (controls.DOWN_P ? 1 : 0) - FlxG.mouse.wheel);
		x = id * FlxG.width;
		var optionsY = FlxG.height / 2;
		if (curSelected > 0) for (i in 0...curSelected)
			optionsY -= members[i].optionHeight;
		optionsY -= members[curSelected].optionHeight / 2;

		for(k=>option in members) {
			if(option == null) continue;

			option.selected = false;
			option.y = __firstFrame ? y : CoolUtil.fpsLerp(option.y, optionsY, 0.25);
			optionsY += option.optionHeight;
			option.x = x + (-50 + (Math.abs(Math.cos((option.y + (optionsHeight / 2) - (FlxG.camera.scroll.y + (FlxG.height / 2))) / (FlxG.height * 1.25) * Math.PI)) * 150));
		}
		if (__firstFrame) {
			__firstFrame = false;
			return;
		}

		if (members.length > 0) {
			members[curSelected].selected = true;
			if (controls.ACCEPT || (FlxG.mouse.justReleased && Main.timeSinceFocus > 0.25)) {
				members[curSelected].onSelect();
				onSelect(members[curSelected]);
			}
			if (controls.LEFT_P)
				members[curSelected].onChangeSelection(-1);
			if (controls.RIGHT_P)
				members[curSelected].onChangeSelection(1);
		}
		if (controls.BACK || FlxG.mouse.justReleasedRight)
			close();
	}

	public function close() {
		onClose(this);
	}

	public function changeSelection(sel:Int, force:Bool = false) {
		if (members.length <= 0 || (sel == 0 && !force)) return;

		CoolUtil.playMenuSFX(SCROLL);
		curSelected = FlxMath.wrap(curSelected + sel, 0, members.length-1);
		if (members[curSelected] is funkin.options.type.Separator) curSelected = FlxMath.wrap(curSelected + sel, 0, members.length-1);
		members[curSelected].selected = true;
		updateMenuDesc();
	}

	public function updateMenuDesc(?customTxt:String) {
		if (parent == null || parent.treeParent == null) return;
		parent.treeParent.updateDesc(customTxt != null ? customTxt : members[curSelected].desc);
	}

	public dynamic function onClose(o:OptionsScreen) {}
	public dynamic function onSelect(o:OptionType) {
		if(o is funkin.options.type.RadioButton) {
			var orb:funkin.options.type.RadioButton = cast o;
			for(e in members) {
				if(e is funkin.options.type.RadioButton) {
					var rb:funkin.options.type.RadioButton = cast e;
					if(rb.forId == orb.forId && rb != o) {
						rb.checked = false;
					}
				}
			}
		}
	}
}