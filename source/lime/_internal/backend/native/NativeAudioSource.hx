// ALL REWRITTEN FROM SCRATCH!!!! -raltyro
package lime._internal.backend.native;

import haxe.Timer;
import haxe.Int64;

import lime.media.openal.AL;
import lime.media.openal.ALBuffer;
import lime.media.openal.ALSource;

#if lime_vorbis
import lime.media.vorbis.Vorbis;
import lime.media.vorbis.VorbisFile;
#end

import lime.math.Vector4;
import lime.media.AudioBuffer;
import lime.media.AudioSource;
import lime.system.System;
import lime.utils.ArrayBufferView;

#if !lime_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(lime.media.AudioBuffer)
@:access(lime.utils.ArrayBufferView)
class NativeAudioSource {
	private static var STREAM_BUFFER_SIZE:Int = 0x4000;
	private static var STREAM_MAX_BUFFERS:Int = 32;
	private static var STREAM_TIMER_FREQUENCY:Int = 100;
	private static var STREAM_BUFFER_FREQUENCY:Int = 6;

	private var parent:AudioSource;
	private var disposed:Bool;
	private var streamed:Bool;
	private var playing:Bool;
	private var completed:Bool;

	private var handle:ALSource;
	private var buffers:Array<ALBuffer>;
	private var unusedBuffers:Array<ALBuffer>;
	private var timer:Timer;
	private var format:Int;
	private var samples:Float;

	private var streamTimer:Timer;
	private var bufferDatas:Array<ArrayBufferView>;
	private var bufferTimes:Array<Float>;
	private var requestBuffers:Int;
	private var queuedBuffers:Int;
	private var toLoop:Int;
	private var streamEnded:Bool;
	private var dataLength:Float;

	private var position:Vector4 = new Vector4();
	private var length:Null<Float>;
	private var loopTime:Null<Float>;
	private var loops:Int;

	public function new(parent:AudioSource) this.parent = parent;

	public function dispose() {
		disposed = true;
		stop();

		if (handle != null) {
			AL.sourcei(handle, AL.BUFFER, AL.NONE);
			AL.deleteSource(handle);
		}
		handle = null;

		if (buffers != null) AL.deleteBuffers(buffers);
		buffers = null;
		bufferDatas = null;
		bufferTimes = null;
		unusedBuffers = null;
	}

	public function init() {
		if (handle != null) return;

		var buffer = parent.buffer;
		if (buffer.channels == 1) format = buffer.bitsPerSample == 8 ? AL.FORMAT_MONO8 : AL.FORMAT_MONO16;
		else format = buffer.bitsPerSample == 8 ? AL.FORMAT_STEREO8 : AL.FORMAT_STEREO16;

		if (disposed = (handle = AL.createSource()) == null) return;
		AL.sourcef(handle, AL.MAX_GAIN, 10);

		if (streamed = buffer.__srcVorbisFile != null) {
			dataLength = (samples = getFloat(buffer.__srcVorbisFile.pcmTotal())) * buffer.channels * (buffer.bitsPerSample == 8 ? 1 : 2);

			var constructor = buffer.bitsPerSample == 8 ? Int8 : Int16;
			buffers = AL.genBuffers(STREAM_MAX_BUFFERS);
			bufferDatas = [for (i in 0...STREAM_MAX_BUFFERS) new ArrayBufferView(STREAM_BUFFER_SIZE, constructor)];
			bufferTimes = [for (i in 0...STREAM_MAX_BUFFERS) 0];
			unusedBuffers = [];
		}
		else {
			samples = (dataLength = getFloat(Int64.make(0, buffer.data.length))) / buffer.channels / (buffer.bitsPerSample == 8 ? 1 : 2);

			if (buffer.__srcBuffer == null && (buffer.__srcBuffer = AL.createBuffer()) != null)
				AL.bufferData(buffer.__srcBuffer, format, buffer.data, buffer.data.length, buffer.sampleRate);

			AL.sourcei(handle, AL.BUFFER, buffer.__srcBuffer);
		}

		if (dataLength == 0) {
			trace('NativeAudioSource Bug! dataLength is 0');
			dispose();
		}
	}

	public function play() {
		if (playing || disposed) return;

		playing = true;
		if (completed) setCurrentTime(0);
		else setCurrentTime(getCurrentTime());
	}

	public function pause() {
		if (!disposed) AL.sourcePause(handle);

		playing = false;
		stopStreamTimer();
		stopTimer();
	}

	public function stop() {
		if (!disposed) {
			if (AL.getSourcei(handle, AL.SOURCE_STATE) != AL.STOPPED) AL.sourceStop(handle);
			if (streamed) {
				AL.sourceUnqueueBuffers(handle, AL.getSourcei(handle, AL.BUFFERS_QUEUED));
				unusedBuffers.resize(0);
			}
			requestBuffers = queuedBuffers = toLoop = 0;
		}

		playing = false;
		stopStreamTimer();
		stopTimer();
	}

	private function complete() {
		completed = true;
		stop();
		parent.onComplete.dispatch();
	}

	// Streaming, atleast for vorbis for now.
	// just incase if we support more than 1 in the future?? which i doubt
	private function streamTell():Float {
		#if lime_vorbis
		/*if (parent.buffer.__srcVorbisFile != null) */return parent.buffer.__srcVorbisFile.timeTell();
		#end
		return 0;
	}

	private function streamSeek(samples:Int64) {
		#if lime_vorbis
		//if (parent.buffer.__srcVorbisFile != null) {
			// There's apparently a bug in libvorbis <= 1.3.4, hhttps://github.com/xiph/vorbis/blob/master/CHANGES#L39
			// But it seems to also happen in this lime libvorbis version which is 1.3.7...? -ralty
			if (samples < 4) parent.buffer.__srcVorbisFile.rawSeek(0); else parent.buffer.__srcVorbisFile.pcmSeek(samples);
		//	break;
		//}
		#end
	}

	private function readToBufferData(data:ArrayBufferView):Int {
		var total = 0, result = 0, wasEOF = false;
		var bigEndian = System.endianness == lime.system.Endian.BIG_ENDIAN, wordSize = parent.buffer.bitsPerSample == 8 ? 1 : 2;
		var size = dataLength - (streamTell() * parent.buffer.sampleRate * parent.buffer.channels * wordSize);
		var n:Int = size < STREAM_BUFFER_SIZE ? Math.floor(size) : STREAM_BUFFER_SIZE;

		var vorbisFile = parent.buffer.__srcVorbisFile;
		while (total < STREAM_BUFFER_SIZE) {
			result = n > 0 ? vorbisFile.read(data.buffer, total, n, bigEndian, wordSize, true) : 0;

			if (result == Vorbis.HOLE) continue;
			else if (result <= Vorbis.EREAD) break;
			else if (result == 0) {
				if (wasEOF || (streamEnded = loops <= toLoop)) break;
				else {
					wasEOF = true;
					toLoop++;

					var samples = getSamples(loopTime != null ? loopTime + parent.offset : parent.offset);
					streamSeek(samples);
					if ((size = dataLength - (getFloat(samples) * parent.buffer.channels * wordSize)) < (n = STREAM_BUFFER_SIZE - total))
						n = Math.floor(size);
				}
			}
			else {
				total += result;
				n -= result;
				wasEOF = false;
			}
		}

		if (total < STREAM_BUFFER_SIZE) data.buffer.fill(total, n, 0);
		if (result < 0) {
			trace('NativeAudioSource Streaming Bug! reading result is $result');
			return result;
		}
		return total;
	}

	private function cycleBuffer() {
		var i = STREAM_MAX_BUFFERS - (queuedBuffers = requestBuffers), n = STREAM_MAX_BUFFERS - 1;
		var data = bufferDatas[i], time = bufferTimes[i];
		while (i < n) {
			bufferDatas[i] = bufferDatas[i + 1];
			bufferTimes[i] = bufferTimes[++i];
		}
		bufferDatas[n] = data;
		bufferTimes[n] = time;
	}

	private function fillBuffer(buffer:ALBuffer):Int {
		var i = STREAM_MAX_BUFFERS - requestBuffers, time = streamTell();
		var decoded = readToBufferData(bufferDatas[i]);

		if (decoded > 0) {
			AL.bufferData(buffer, format, bufferDatas[i], decoded, parent.buffer.sampleRate);
			bufferTimes[i] = time;
			cycleBuffer();
		}

		return decoded;
	}

	private function streamRun() {
		#if lime_vorbis
		if (parent == null || parent.buffer == null || handle == null) return dispose();
		if (!playing || disposed) stopStreamTimer();

		try {
			var processed = AL.getSourcei(handle, AL.BUFFERS_PROCESSED), n = STREAM_BUFFER_FREQUENCY, buffer;
			while (processed-- > 0) {
				buffer = AL.sourceUnqueueBuffer(handle);
				if (!streamEnded && --n > 0 && fillBuffer(buffer) > 0) AL.sourceQueueBuffer(handle, buffer);
				else {
					queuedBuffers = --requestBuffers;
					unusedBuffers.push(buffer);
				}
			}

			if (!streamEnded) {
				if (unusedBuffers.length != 0) {
					requestBuffers++;
					if (fillBuffer(buffer = unusedBuffers.pop()) > 0) {
						queuedBuffers = requestBuffers;
						AL.sourceQueueBuffer(handle, buffer);
					}
					else {
						requestBuffers--;
						unusedBuffers.push(buffer);
					}
				}
				else if (queuedBuffers < STREAM_MAX_BUFFERS) {
					if (fillBuffer(buffer = buffers[requestBuffers++]) > 0) AL.sourceQueueBuffer(handle, buffer);
					else requestBuffers--;
				}
			}

			if (AL.getSourcei(handle, AL.SOURCE_STATE) == AL.STOPPED) {
				AL.sourcePlay(handle);
				resetTimer((getLength() - getCurrentTime()) / getPitch());
			}
		}
		catch(e) trace('NativeAudioSource Bug! in streamRun $e');
		#end
	}

	// Timers
	inline function stopStreamTimer() if (streamTimer != null) streamTimer.stop();

	private function resetStreamTimer() {
		stopStreamTimer();
		if (streamed) (streamTimer = new Timer(STREAM_TIMER_FREQUENCY)).run = streamRun;
	}

	inline function stopTimer() if (timer != null) timer.stop();

	private function resetTimer(timeRemaining:Float) {
		stopTimer();
		(timer = new Timer(timeRemaining)).run = timer_onRun;
	}

	private function timer_onRun() {
		var timeRemaining = (getLength() - getCurrentTime()) / getPitch();
		if (timeRemaining > 30 && AL.getSourcei(handle, AL.SOURCE_STATE) == AL.PLAYING) {
			resetTimer(timeRemaining);
			return;
		}

		if (loops == 0) {
			complete();
			return;
		}

		if (toLoop <= 0) {
			var start = loopTime != null ? loopTime : 0;
			setLoops(--loops);
			if (start > 0 || AL.getSourcei(handle, AL.SOURCE_STATE) != AL.PLAYING) setCurrentTime(start);
		}
		else {
			if ((loops -= toLoop) < 0) loops = 0;
			toLoop = 0;
		}

		parent.onLoop.dispatch();
	}

	// Get & Set Methods
	public function getCurrentTime():Float {
		if (completed) return getLength();
		else if (!disposed) {
			var time = ((streamed ? bufferTimes[STREAM_MAX_BUFFERS - queuedBuffers] : 0) + AL.getSourcef(handle, AL.SEC_OFFSET)) * 1000 - parent.offset;
			if (loops > 0 && time > getLength()) {
				var start = (loopTime != null ? Math.max(0, loopTime) : 0) + parent.offset;
				return ((time - start) % (getLength() - start)) + start;
			}
			else if (time > 0) return time;
		}
		return 0;
	}

	public function setCurrentTime(value:Float):Float {
		if (disposed) return value;

		if (streamed) {
			AL.sourceStop(handle);
			AL.sourceUnqueueBuffers(handle, AL.getSourcei(handle, AL.BUFFERS_QUEUED));

			unusedBuffers.resize(0);
			streamSeek(getSamples(value + parent.offset));
		}
		else
			AL.sourcei(handle, AL.SAMPLE_OFFSET, getSamples(value + parent.offset));

		if (playing) {
			var timeRemaining = (getLength() - value) / AL.getSourcef(handle, AL.PITCH);
			if (timeRemaining > 0) {
				if (streamed) {
					for (i in 0...(requestBuffers = queuedBuffers = STREAM_BUFFER_FREQUENCY))
						if (fillBuffer(buffers[i]) > 0) AL.sourceQueueBuffer(handle, buffers[i]);

					resetStreamTimer();
				}
				resetTimer(timeRemaining);
				AL.sourcePlay(handle);
			}
			else {
				stopStreamTimer();
				complete();
			}
		}

		return value;
	}

	inline private function getRealLength():Float return samples / parent.buffer.sampleRate * 1000;
	public function getLength():Null<Float> {
		return if (length == null) getRealLength() - parent.offset;
		else length - parent.offset;
	}

	public function setLength(value:Null<Float>):Null<Float> {
		if (value == length || disposed) return length = value;

		var buffer = parent.buffer, wordSize = buffer.bitsPerSample == 8 ? 1 : 2;
		if ((length = value) == null) dataLength = streamed ? samples * buffer.channels * wordSize : getFloat(Int64.make(0, buffer.data.length));
		else dataLength = Math.ffloor(Math.max(0, Math.min(value, getRealLength())) / 1000 * buffer.sampleRate) * buffer.channels * wordSize;

		if (playing) {
			if (streamed) setCurrentTime(getCurrentTime());
			else {
				var timeRemaining = ((getLength() - parent.offset) - getCurrentTime()) / getPitch();
				if (timeRemaining > 0) resetTimer(timeRemaining);
			}
		}
		return value;
	}

	public function getPitch():Float {
		return if (disposed) 1;
		else AL.getSourcef(handle, AL.PITCH);
	}

	public function setPitch(value:Float):Float {
		if (disposed || value == AL.getSourcef(handle, AL.PITCH)) return value;
		if (playing) {
			if (value <= 0) stopTimer();
			else {
				var timeRemaining = (getLength() - getCurrentTime()) / value;
				if (timeRemaining > 0) resetTimer(timeRemaining);
			}
		}
		AL.sourcef(handle, AL.PITCH, value);
		return value;
	}

	public function getGain():Float {
		if (disposed) return 1;
		return AL.getSourcef(handle, AL.GAIN);
	}

	public function setGain(value:Float):Float {
		if (!disposed) AL.sourcef(handle, AL.GAIN, value);
		return value;
	}

	inline public function getLoops():Int return loops;

	inline public function setLoops(value:Int):Int {
		if (!streamed && !disposed) AL.sourcei(handle, AL.LOOPING, (loopTime <= 0 && value > 0) ? AL.TRUE : AL.FALSE);
		else if (loops == 0 && value > 0) setCurrentTime(getCurrentTime());
		if (value < 0) return loops = 0;
		return loops = value;
	}

	inline public function getLoopTime():Float return loopTime;

	inline public function setLoopTime(value:Float):Float {
		if (!streamed && !disposed) AL.sourcei(handle, AL.LOOPING, (value <= 0 && loops > 0) ? AL.TRUE : AL.FALSE);
		return loopTime = value;
	}

	public function getLatency():Float {
		/*#if (lime >= "8.3.0")
		if (AL.isExtensionPresent("AL_SOFT_source_latency")) {
			final offsets = AL.getSourcedvSOFT(handle, AL.SEC_OFFSET_LATENCY_SOFT, 2);
			if (offsets != null) return offsets[1] * 1000;
		}
		#end*/
		return 0;
	}

	public function getPosition():Vector4 return position;

	public function setPosition(value:Vector4):Vector4 {
		position.x = value.x;
		position.y = value.y;
		position.z = value.z;
		position.w = value.w;

		if (!disposed) {
			AL.distanceModel(AL.NONE);
			AL.source3f(handle, AL.POSITION, position.x, position.y, position.z);
		}
		return position;
	}

	inline private function getFloat(x:Int64):Float return x.high * 4294967296. + (x.low >>> 0);
	inline private function getSamples(ms:Float):Int64 return Int64.fromFloat(Math.max(0, Math.min(ms / 1000 * parent.buffer.sampleRate, samples)));
}
