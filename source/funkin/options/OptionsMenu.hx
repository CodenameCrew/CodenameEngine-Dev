package funkin.options;

import funkin.backend.system.framerate.Framerate;
import funkin.options.TreeMenu;
import funkin.options.categories.*;
import funkin.options.type.*;
import funkin.options.type.Checkbox;
import haxe.xml.Access;

class OptionsMenu extends TreeMenu {
	public static var mainOptions:Array<OptionCategory> = [
		{  // name and desc are actually the translations ids!  - Nex
			name: 'optionsTree.controls-name',
			desc: 'optionsTree.controls-desc',
			state: null,
			substate: (name:String, desc:String) -> {
				return new funkin.options.keybinds.KeybindsOptions();
			}
		},
		{
			name: 'optionsTree.gameplay-name',
			desc: 'optionsTree.gameplay-desc',
			suffix: " >",
			state: GameplayOptions
		},
		{
			name: 'optionsTree.appearance-name',
			desc: 'optionsTree.appearance-desc',
			suffix: " >",
			state: AppearanceOptions
		},
		#if TRANSLATIONS_SUPPORT
		{
			name: 'optionsTree.language-name',
			desc: 'optionsTree.language-desc',
			suffix: " >",
			state: LanguageOptions
		},
		#end
		{
			name: 'optionsTree.miscellaneous-name',
			desc: 'optionsTree.miscellaneous-desc',
			suffix: " >",
			state: MiscOptions
		},
		{
			name: "Debug Options",
			desc: "debugOptions",
			suffix: " >",
			state: DebugOptions
		}
	];

	var bg:FlxSprite;

	var addedDebugOptions:Bool = !Options.devMode;
	var debugModeButton:OptionType;
	var debugModeIndex:Int = mainOptions.length - 1;

	public override function create() {
		super.create();

		CoolUtil.playMenuSong();

		DiscordUtil.call("onMenuLoaded", ["Options Menu"]);

		bg = new FlxSprite(-80).loadAnimatedGraphic(Paths.image('menus/menuBGBlue'));
		// bg.scrollFactor.set();
		bg.scale.set(1.15, 1.15);
		bg.updateHitbox();
		bg.screenCenter();
		bg.scrollFactor.set();
		bg.antialiasing = true;
		add(bg);

		main = new OptionsScreen("optionsMenu.header.title", "optionsMenu.header.desc", [for(o in mainOptions) {
			new TextOption(o.name, o.desc, o.suffix, function() {
				if (o.substate != null) {
					persistentUpdate = false;
					persistentDraw = true;
					if (o.substate is MusicBeatSubstate) {
						openSubState(o.substate);
					} else if(Reflect.isFunction(o.substate)) {
						var substate:(name:String, desc:String) -> MusicBeatSubstate = o.substate;
						openSubState(substate(o.name, o.desc));
					} else { // o.substate is Class<OptionsScreen>
						openSubState(Type.createInstance(o.substate, [o.name, o.desc]));
					}
				} else {
					if (o.state is OptionsScreen) {
						optionsTree.add(o.state);
					} else if(Reflect.isFunction(o.state)) {
						var state:(name:String, desc:String) -> OptionsScreen = o.state;
						optionsTree.add(state(o.name, o.desc));
					} else { // o.state is Class<OptionsScreen>
						optionsTree.add(Type.createInstance(o.state, [o.name, o.desc]));
					}
				}
			});
		}]);

		for (i in funkin.backend.assets.ModsFolder.getLoadedMods()) {
			var xmlPath = Paths.xml('config/options/LIB_$i');

			if (Paths.assetsTree.existsSpecific(xmlPath, "TEXT")) {
				var access:Access = null;
				try access = new Access(Xml.parse(Paths.assetsTree.getSpecificAsset(xmlPath, "TEXT")))
				catch(e) Logs.trace('Error while parsing options.xml: ${Std.string(e)}', ERROR);
				if (access != null) for (o in parseOptionsFromXML(access)) main.add(o);
			}
		}

		doDebugOptionThing();
	}

	public override function onMenuClose(m:OptionsScreen) {
		doDebugOptionThing();
	}

	public function reloadStrings() {
		for(o in main.members) {
			o.reloadStrings();
		}
		optionsTree.reloadStrings();
		reloadLabels();
	}

	public override function exit() {
		Options.save();
		Options.applySettings();
		super.exit();
	}

	function doDebugOptionThing() {
		if ((Options.devMode && !addedDebugOptions) || (!Options.devMode && addedDebugOptions)) {
			trace((addedDebugOptions ? "remove" : "add") + " option");
			addedDebugOptions = !addedDebugOptions;
			if (debugModeButton == null) debugModeButton = main.members[debugModeIndex];
			if (addedDebugOptions)
				main.add(debugModeButton);
			else
				main.remove(debugModeButton);
		}
	}

	/**
	 * XML STUFF
	 */
	public function parseOptionsFromXML(xml:Access):Array<OptionType> {
		var options:Array<OptionType> = [];

		for(node in xml.elements) {
			if (!node.has.name) {
				Logs.warn("An option node requires a name attribute.");
				continue;
			}
			var name = node.getAtt("name");
			var desc = node.getAtt("desc").getDefault("optionsMenu.desc-missing");

			switch(node.name) {
				case "checkbox":
					if (!node.has.id) {
						Logs.warn("A checkbox option requires an \"id\" for option saving.");
						continue;
					}
					options.push(new Checkbox(name, desc, node.att.id, FlxG.save.data));

				case "number":
					if (!node.has.id) {
						Logs.warn("A number option requires an \"id\" for option saving.");
						continue;
					}
					options.push(new NumOption(name, desc, Std.parseFloat(node.att.min), Std.parseFloat(node.att.max), Std.parseFloat(node.att.change), node.att.id, null, FlxG.save.data));
				case "choice":
					if (!node.has.id) {
						Logs.warn("A choice option requires an \"id\" for option saving.");
						continue;
					}

					var optionOptions:Array<Dynamic> = [];
					var optionDisplayOptions:Array<String> = [];

					for(choice in node.elements) {
						optionOptions.push(choice.att.value);
						optionDisplayOptions.push(choice.att.name);
					}

					if(optionOptions.length > 0)
						options.push(new ArrayOption(name, desc, optionOptions, optionDisplayOptions, node.att.id, null, FlxG.save.data));

				case "menu":
					options.push(new TextOption(name + " >", desc, function() {
						optionsTree.add(new OptionsScreen(name, desc, parseOptionsFromXML(node)));
					}));
			}
		}

		return options;
	}
}