package funkin.options.categories;

import funkin.backend.utils.NativeAPI;

class DebugOptions extends OptionsScreen {
	public override function new(title:String, desc:String) {
		super(title, desc, "DebugOptions.");

		add(new TextOption(
			getName("showConsole"),
			getDesc("showConsole"),
			function() NativeAPI.allocConsole()));
		add(new Checkbox(
			getName("editorsResizable"),
			getDesc("editorsResizable"),
			"editorsResizable"));
		add(new Checkbox(
			getName("bypassEditorsResize"),
			getDesc("bypassEditorsResize"),
			"bypassEditorsResize"));
		add(new Checkbox(
			getName("editorSFX"),
			getDesc("editorSFX"),
			"editorSFX"));
		add(new Checkbox(
			getName("editorCharterPrettyPrint"),
			getDesc("editorCharterPrettyPrint"),
			"editorCharterPrettyPrint"));
		add(new Checkbox(
			getName("editorCharacterPrettyPrint"),
			getDesc("editorCharacterPrettyPrint"),
			"editorCharacterPrettyPrint"));
		add(new Checkbox(
			getName("editorStagePrettyPrint"),
			getDesc("editorStagePrettyPrint"),
			"editorStagePrettyPrint"));
		add(new Checkbox(
			getName("intensiveBlur"),
			getDesc("intensiveBlur"),
			"intensiveBlur"));
		add(new Checkbox(
			getName("charterAutoSaves"),
			getDesc("charterAutoSaves"),
			"charterAutoSaves"));
		add(new NumOption(
			getName("charterAutoSaveTime"),
			getDesc("charterAutoSaveTime"),
			60, 60*10, 30,
			"charterAutoSaveTime"
		));
		add(new NumOption(
			getName("charterAutoSaveWarningTime"),
			getDesc("charterAutoSaveWarningTime"),
			0, 15, 1,
			"charterAutoSaveWarningTime"
		));
		add(new Checkbox(
			getName("charterAutoSavesSeparateFolder"),
			getDesc("charterAutoSavesSeparateFolder"),
			"charterAutoSavesSeparateFolder"));
	}
}