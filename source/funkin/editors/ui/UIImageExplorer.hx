package funkin.editors.ui;

import flixel.util.typeLimit.OneOfTwo;
import flixel.text.FlxText.FlxTextFormat;
import flixel.text.FlxText.FlxTextFormatMarkerPair;
import flxanimate.data.SpriteMapData.AnimateAtlas;
import flixel.graphics.frames.FlxFramesCollection;
import haxe.Json;
import haxe.io.Bytes;
import haxe.io.Path;
import openfl.display.BitmapData;
import sys.FileSystem;
import sys.io.File;

using StringTools;
using funkin.backend.utils.BitmapUtil;
using flixel.util.FlxSpriteUtil;

typedef ImageSaveData = {
	var imageName:String;
	var isAtlas:Bool;
	var imageFiles:Map<String, OneOfTwo<String, Bytes>>;
}

// TODO: make this limited if on web
class UIImageExplorer extends UIFileExplorer {
	private var allowAtlases:Bool = true;

	public function new(x:Float, y:Float, image:String, ?w:Int, ?h:Int, ?onFile:(String, Bytes)->Void) {
		super(x, y, w, h, "png, jpg", function (filePath, file) {
			if (filePath != null && file != null) uploadImage(filePath, file);
			if (onFile != null) onFile(filePath, file);
		});

		deleteButton.bWidth = 26;
		deleteButton.bHeight = 26;

		if (image != null) {
			var fullImagePath:String = '${Path.normalize(Sys.getCwd())}/${Paths.image(image)}'.replace('/', '\\');
			var noExt = Path.withoutExtension(fullImagePath);
			if (FileSystem.exists('$noExt\\spritemap1.png'))
				fullImagePath = '$noExt\\spritemap1.png';
	
			if (FileSystem.exists(fullImagePath))
				loadFile(fullImagePath);
		}
	}

	public var isAtlas:Bool = false;

	static var ANIMATE_ATLAS_REGEX = ~/^(?:Animation\.json|spritemap(?:\d+)?\.json)$/i; // no .zip atlases tho
	static var SPRITEMAP_JSON_REGEX = ~/^(?:spritemap(?:\d+)?\.json)$/i;
	static var SPRITEMAP_PNG_REGEX = ~/^(?:spritemap(?:\d+)?\.png)$/i;

	public var imageName:String = null;
	public var imageFiles:Map<String, OneOfTwo<String, Bytes>> = [];
	public var animationList:Array<String> = [];

	public var fileText:UIText;

	public var maxSize:FlxPoint = FlxPoint.get(700, 500);

	public function uploadImage(filePath:String, file:Bytes) {
		__resetData();

		var imagePath:Dynamic = Path.normalize(filePath);

		var directoryPath:String = Path.directory(imagePath);
		var fileName:String = Path.withoutDirectory(imagePath).toLowerCase();
		var files:Array<String> = [];

		// CHECK ATLAS
		if(allowAtlases && ANIMATE_ATLAS_REGEX.match(fileName)) {
			// check if directory has the other files
			files = FileSystem.readDirectory(directoryPath);
			var hasAnimationJson:Bool = false;
			var hasSpritemapJson:Bool = false;
			for(file in files) {
				if(file == "Animation.json")
					hasAnimationJson = true;
				else if(SPRITEMAP_JSON_REGEX.match(file.toLowerCase()))
					hasSpritemapJson = true;

				if(hasAnimationJson && hasSpritemapJson) {
					isAtlas = true;
					break;
				}
			}
		} else if(allowAtlases && Path.extension(fileName) == "png") {
			// check if the spritemap json files point to the image
			files = FileSystem.readDirectory(directoryPath);
			var hasAnimationJson:Bool = false;
			var foundSpritemapJson:Bool = false;
			for(file in files) {
				if(SPRITEMAP_JSON_REGEX.match(file)) {
					var content:String = CoolUtil.removeBOM(File.getContent(Path.join([directoryPath, file])));
					var json:AnimateAtlas = Json.parse(content);
					if(json.meta.image.toLowerCase() == fileName.toLowerCase())
						foundSpritemapJson = true;
				} else if(file == "Animation.json")
					hasAnimationJson = true;

				if(hasAnimationJson && foundSpritemapJson) {
					isAtlas = true;
					break;
				}
			}
		}

		// IF ATLAS FIND SPRITMAPS
		var spritemaps:Array<String> = [];
		var spritemapImages:Array<String> = [];
		if(isAtlas) {
			// this doesn't check for gaps in the numbering
			for(file in files)
				if(SPRITEMAP_JSON_REGEX.match(file))
					spritemaps.push(file);

			spritemaps.sort(Reflect.compare);
			for(spritemap in spritemaps) {
				var content:String = CoolUtil.removeBOM(File.getContent(Path.join([directoryPath, spritemap])));
				var json:AnimateAtlas = Json.parse(content);
				var imageToFind:String = json.meta.image.toLowerCase();
				for(file in files) {
					// lowercase since windows does case insensitive stuff, so we use lowercase to match behavior on mac and linux
					// and we also store the data from the filesystem instead of the json.meta.image
					if(file.toLowerCase() == imageToFind) {
						spritemapImages.push(file);
						break;
					}
				}
			}

			if(spritemapImages.length == 0)
				isAtlas = false;
		}

		// GATHER ANIMATIONS/DATA FILES!!!
		var frames:FlxFramesCollection = null;
		if (isAtlas) {
			var dataPath:String = '$directoryPath/Animation.json'.replace('/', '\\');

			if (FileSystem.exists(dataPath)) {
				var dataPathFile:String = File.getContent(dataPath);
				animationList = CoolUtil.getAnimsListFromAtlas(cast haxe.Json.parse(dataPathFile));

				imageFiles.set(Path.withoutDirectory(dataPath), dataPathFile);
			}
		} else {
			var dataPathExt:String = CoolUtil.imageHasFrameData(imagePath);
			var dataPath:String = Path.withExtension(imagePath, dataPathExt);
			var dataPathFile:String = !isAtlas && dataPathExt != null ? File.getContent(dataPath) : null;
	
			if (dataPathExt != null) {
				frames = CoolUtil.loadFramesFromData(dataPathFile, dataPathExt);
				animationList = CoolUtil.getAnimsListFromFrames(frames, dataPathExt);

				imageFiles.set(Path.withoutDirectory(dataPath), dataPathFile);
			}
		}

		// GATHER INFO!!!
		var size:Float = 0;
		var image:BitmapData = null;
		if (isAtlas && spritemapImages.length > 0) {
			var spritemapPath:String = Path.join([directoryPath, spritemapImages[0]]);

			imagePath = Path.normalize(spritemapPath);
			directoryPath = Path.directory(imagePath);
			fileName = Path.withoutDirectory(imagePath).toLowerCase();

			for(spritemap in spritemapImages) {
				var spritemapPath:String = Path.join([directoryPath, spritemap]);

				var info = FileSystem.stat(spritemapPath);
				size += info.size;

				spritemapPath = spritemapPath.replace('/', '\\');
				imageFiles.set(Path.withoutDirectory(spritemapPath), sys.io.File.getBytes(spritemapPath));
			}

			file = cast sys.io.File.getBytes(filePath = spritemapPath);
			image = BitmapData.fromBytes(file).crop();

		} else {
			size = file.length;
			image = BitmapData.fromBytes(file).crop();

			imageFiles.set(Path.withoutDirectory(imagePath), file);
		}

		// DISPLAY IMAGE!!
		uiElement = new FlxSprite().loadGraphic(image);
		var imageScale:Float = 1;
		if (uiElement.width < Math.min(300, maxSize.x) || uiElement.height < Math.min(200, maxSize.y))
			imageScale = Math.max(Math.min(300, maxSize.x) / uiElement.width, Math.min(200, maxSize.y) / uiElement.height);
		else if (uiElement.width > maxSize.x || uiElement.height > maxSize.y)
			imageScale = Math.min(maxSize.x/uiElement.width, maxSize.y/uiElement.height);
		uiElement.scale.set(imageScale, imageScale);
		uiElement.updateHitbox();

		bWidth = Std.int(uiElement.width)+32; bHeight = Std.int(uiElement.height)+32+deleteButton.bHeight+4;
		uiElement.x = x+16; uiElement.y = y+16+deleteButton.bHeight+4;

		uiElement.antialiasing = true;
		members.push(uiElement);

		if (!isAtlas && frames != null) {
			for (frame in frames.frames) {
				var rect = frame.frame;
				uiElement.drawRect(rect.x, rect.y, rect.width, rect.height, 0x00161E87, {thickness: Std.int(1.75/imageScale), color: 0xFF11178C});
			}
		}
		// GENERATE TEXT!!!
		imagePath = new Path(imagePath);
		imageName = isAtlas ? Path.withoutDirectory(directoryPath) : imagePath.file;

		var message = new StringBuf();
		if (isAtlas) message.add('${imageName}/');
		message.add('${imagePath.file}.${imagePath.ext}');
		message.add(' (${CoolUtil.getSizeString(size)}');

		if (animationList.length > 0) {
			if(animationList.length == 1) message.add(', ${animationList.length} ${isAtlas ? "Symbol" : "Animation"} Found');
			else message.add(', ${animationList.length} ${isAtlas ? "Symbol" : "Animation"}s Found');
		} else message.add(', #NO ${isAtlas ? "Symbol" : "Animation"}s Found#');

		if (isAtlas) {
			if(spritemaps.length == 1) message.add(', ${spritemaps.length} Spritemap Found');
			else message.add(', ${spritemaps.length} Spritemaps Found');
		}
		message.add(')');
		message.add(isAtlas ? " - Atlas" : " - Spritemap");

		fileText = new UIText(x+20, y+16, bWidth-20-deleteButton.bWidth-16, "");
		fileText.applyMarkup(message.toString(), [new FlxTextFormatMarkerPair(new FlxTextFormat(0xFFAD1212), "#")]);
		members.push(fileText);

		deleteButton.x = x + bWidth - deleteButton.bWidth - 16;
		deleteButton.y = y + 12;

		deleteIcon.x = deleteButton.x + deleteButton.bWidth/2 - 8;
		deleteIcon.y = deleteButton.y + deleteButton.bHeight/2 - 8;
	}

	public inline function getSaveData():ImageSaveData {
		return {
			imageName: this.imageName, 
			isAtlas: this.isAtlas, 
			imageFiles: this.imageFiles
		};
	}

	public inline function saveFiles(directory:String, ?onFinishSaving:Void->Void, ?checkExisting:Bool = true) {
		UIImageExplorer.saveFilesGlobal(getSaveData(), directory, onFinishSaving, checkExisting);
	}

	public static function saveFilesGlobal(imageData:ImageSaveData, directory:String, ?onFinishSaving:Void->Void, ?checkExisting:Bool = true) {
		if (imageData.isAtlas) directory += '/${imageData.imageName}';

		var alreadlyExistingFiles:Array<String> = [];
		for (name => file in imageData.imageFiles)
			if (FileSystem.exists('$directory/$name'))
				alreadlyExistingFiles.push('$directory/$name');

		function deleteExistingFiles() {
			for (file in alreadlyExistingFiles)
				FileSystem.deleteFile(file);
			alreadlyExistingFiles = [];
		}

		function acuttalySaveFiles() {
			for (name => file in imageData.imageFiles)
				if (!alreadlyExistingFiles.contains('$directory/$name')) {
					CoolUtil.safeSaveFile('$directory/$name', file);
					trace('SAVED: $directory/$name');
				}

			if (onFinishSaving != null) onFinishSaving();
		}

		if (alreadlyExistingFiles.length > 0 && checkExisting) @:privateAccess {
			(FlxG.state.subState != null && !FlxG.state._requestSubStateReset ? FlxG.state.subState : FlxG.state).openSubState(new UIWarningSubstate("Alreadly Existing Files!!!", 
				"The following files alreadly exist: \n\n" + alreadlyExistingFiles.join('\n') + "\n\nIMPORTANT: OVERRIDING CAN NOT BE UNDONE!!!!!!!!", 
				[ {
					label: "Override Files",
					color: 0xFFFF0000,
					onClick: (_) -> {
						deleteExistingFiles();
						acuttalySaveFiles();
					}
				}, 
				{
					label: "Use Existing",
					onClick: (_) -> {if (onFinishSaving != null) onFinishSaving();}
				}
			], false));
		} else acuttalySaveFiles();
	}

	public override function removeFile() {
		__resetData();
		bWidth = 320; bHeight = 58;

		members.remove(fileText);
		fileText.destroy();

		super.removeFile();
	}

	@:noCompletion inline function __resetData() {
		imageFiles.clear(); isAtlas = false; animationList = [];
	}

	public override function destroy() {
		maxSize.put();
		super.destroy();
	}
}