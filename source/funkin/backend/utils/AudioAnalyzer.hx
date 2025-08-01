package funkin.backend.utils;

import flixel.sound.FlxSound;
import lime.media.AudioBuffer;
import lime.utils.ArrayBufferView.ArrayBufferIO;
import lime.utils.ArrayBuffer;

#if (lime_cffi && lime_vorbis)
import lime.media.vorbis.Vorbis;
import lime.media.vorbis.VorbisFile;
#end

typedef AudioAnalyzerCallback = Int->Int->Void;

/**
 * An utility that analyze FlxSounds,
 * can be used to make waveform or real-time audio visualizer.
 * 
 * FlxSound.amplitude does work in CNE so if any case if your only checking for peak of current
 * time, use that instead.
 */
class AudioAnalyzer {
	/**
	 * Get bytes from an audio buffer with specified position and wordSize
	 * @param buffer The audio buffer to get byte from.
	 * @param position The specified position to get the byte from the audio buffer.
	 * @param wordSize How many bytes to get with to one byte (Usually it's bitsPerSample / 8 or bitsPerSample >> 3).
	 * @return Byte from the audio buffer with specified position.
	 */
	public static function getByte(buffer:ArrayBuffer, position:Int, wordSize:Int):Int {
		if (wordSize == 2) return inline ArrayBufferIO.getInt16(buffer, position);
		else if (wordSize == 3) {
			var b = inline ArrayBufferIO.getUint16(buffer, position) | (buffer.get(position + 2) << 16);
			if (b & 0x800000 != 0) return b - 0x1000000;
			else return b;
		}
		else if (wordSize == 4) return inline ArrayBufferIO.getInt32(buffer, position);
		else return inline ArrayBufferIO.getUint8(buffer, position) - 128;
	}

	/**
	 * Gets levels from the frequencies with specified sample rate.
	 * @param frequencies Frequencies input.
	 * @param sampleRate Sample Rate input.
	 * @param barCount How much bars to get.
	 * @param levels The output for getting the values, to avoid memory leaks (Optional).
	 * @param delta How much delta for smoothen the values from the previous levels values (Optional).
	 * @param minDb The minimum decibels to cap (Optional, default -70.0).
	 * @param maxDb The maximum decibels to cap (Optional, default -10.0).
	 * @param minFreq The minimum frequency to cap (Optional, default 20.0).
	 * @param maxFreq The maximum frequency to cap (Optional, default 22000.0).
	 * @return Output of levels/bars
	 */
	public static function getLevelsFromFrequencies(frequencies:Array<Float>, sampleRate:Int, barCount:Int, ?levels:Array<Float>, delta = 0.0, minDb = -70.0, maxDb = -10.0, minFreq = 20.0, maxFreq = 22000.0):Array<Float> {
		if (levels == null) levels = [];
		levels.resize(barCount);

		var logMin = Math.log(minFreq), logMax = Math.log(maxFreq);
		var logRange = logMax - logMin, dbRange = maxDb - minDb, n = frequencies.length;
		inline function calculateScale(i:Int)
			return CoolUtil.bound(Math.exp(logMin + (logRange * i / (barCount + 1))) * n * 2 / sampleRate, 0, n - 1);

		var s1 = calculateScale(0), s2;
		var i1 = Math.floor(s1), i2;
		var v, range;
		for (i in 0...barCount) {
			if ((range = (s2 = calculateScale(i + 1)) - s1) < 1) {
				i2 = Math.ceil(s2);
				if (i2 == i1) v = frequencies[i1] * range;
				else v = (frequencies[i1] + (frequencies[i2] - frequencies[i1]) * (s1 - i1)) * range;
			}
			else {
				v = frequencies[i1] * (Math.ceil(s1) - i1);
				if (i1 != (i2 = Math.floor(s2))) {
					while (++i1 < i2) v += frequencies[i1];
					v += frequencies[i2] * (s2 - Math.floor(s2));
				}
			}
			i1 = Math.floor(s1 = s2);

			v = ((20 * Math.log(v) / 2.302585092994046) - minDb) / dbRange;
			if (delta > 0 && delta < 1 && v < levels[i]) levels[i] -= Math.pow(levels[i] - v, 2.302585092994046) * delta;
			else levels[i] = v;
		}

		return levels;
	}

	/**
	 * The current sound to analyze.
	 */
	public var sound:FlxSound;

	/**
	 * How much samples for the fft to get.
	 * Usually for getting the levels or frequencies of the sound.
	 * 
	 * Has to be power of two, or it won't work.
	 */
	public var fftN(default, set):Int;

	/**
	 * The current buffer from sound.
	 */
	public var buffer(default, null):AudioBuffer;

	/**
	 * The current byteSize from buffer.
	 * Example the byteSize of 16 BitsPerSample is 32768 (1 << 16-1)
	 */
	public var byteSize(default, null):Int;

	var __toBits:Float;
	var __wordSize:Int;
	var __sampleSize:Int;

	#if (lime_cffi && lime_vorbis)
	var __vorbis:VorbisFile;
	var __buffer:ArrayBuffer;
	var __bufferSize:Int;
	var __bufferLastSize:Int;
	var __bufferTime:Float;
	var __bufferLastTime:Float;
	#end

	// analyze
	var __min:Array<Int> = [];
	var __max:Array<Int> = [];
	var __minByte:Int;
	var __maxByte:Int;

	// samples
	var __sampleIndex:Int;
	var __sampleOutputLength:Int;
	var __sampleOutput:Array<Float>;

	// fft
	var __N2:Int;
	var __logN:Int;
	var __freqSamples:Array<Float>;
	var __reverseIndices:Array<Int> = [];
	var __factors:Array<Int> = [];
	var __windows:Array<Float> = [];
	var __twiddleReals:Array<Float> = [];
	var __twiddleImags:Array<Float> = [];
	var __freqReals:Array<Float> = [];
	var __freqImags:Array<Float> = [];

	// levels
	var __frequencies:Array<Float>;

	/**
	 * Creates an analyzer for specified FlxSound
	 * @param sound An FlxSound to analyze.
	 * @param fftN How much samples for fft to get (Optional, default 2048).
	 */
	public function new(sound:FlxSound, fftN = 2048) {
		this.sound = sound;
		this.fftN = fftN;
		__check();
	}

	function __check() if (sound.buffer != buffer) {
		byteSize = 1 << ((buffer = sound.buffer).bitsPerSample - 1);

		#if (lime_cffi && lime_vorbis)
		__vorbis = null;
		__bufferLastSize = 0;
		__bufferTime = Math.NaN;
		__bufferLastTime = Math.NaN;
		#end

		__toBits = buffer.sampleRate / 1000 * (__sampleSize = buffer.channels * (__wordSize = buffer.bitsPerSample >> 3));
		__min.resize(buffer.channels);
		__max.resize(buffer.channels);
	}

	inline function set_fftN(v:Int):Int {
		if (fftN == (fftN = nextPow2(v))) return fftN;

		__logN = Math.floor(Math.log(fftN) / Math.log(2));
		__N2 = fftN >> 1;
		__freqReals.resize(fftN);
		__freqImags.resize(fftN);
		__reverseIndices.resize(fftN);
		__windows.resize(fftN);
		__twiddleReals.resize(fftN);
		__twiddleImags.resize(fftN);

		var f, a;
		for (i in 0...fftN) {
			f = i / (fftN - 1);
			__windows[i] = 0.42 - 0.5 * Math.cos(2 * Math.PI * f) + 0.08 * Math.cos(4 * Math.PI * f);
			__reverseIndices[i] = __bitReverse(i);
			__twiddleReals[i] = Math.cos(a = -2 * Math.PI * i / fftN);
			__twiddleImags[i] = Math.sin(a);
		}

		__factors.resize(0);

		var inv = fftN;
		/*while (inv % 4 == 0) {
			__factors.push(4);
			inv >>= 2;
		}*/

		while (inv % 2 == 0) {
			__factors.push(2);
			inv >>= 1;
		}

		return fftN;
	}

	inline function nextPow2(x:Int):Int {
		var p = 1;
		while (p < x) p <<= 1;
		return p;
	}

	inline function __bitReverse(x:Int):Int {
		var y = 0, i = __logN;
		while (i > 0) {
			y = (y << 1) | (x & 1);
			x >>= 1;
			i--;
		}
		return y;
	}

	/**
	 * Gets levels from an attached FlxSound from startPos, basically a minimized of frequencies.
	 * @param startPos Start Position to get from sound in milliseconds.
	 * @param barCount How much bars to get.
	 * @param levels The output for getting the values, to avoid memory leaks (Optional).
	 * @param delta How much delta for smoothen the values from the previous levels values (Optional).
	 * @param minDb The minimum decibels to cap (Optional, default -70.0).
	 * @param maxDb The maximum decibels to cap (Optional, default -10.0).
	 * @param minFreq The minimum frequency to cap (Optional, default 20.0).
	 * @param maxFreq The maximum frequency to cap (Optional, default 22000.0).
	 * @return Output of levels/bars
	 */
	public function getLevels(startPos:Float, barCount:Int, ?levels:Array<Float>, ?delta:Float, ?minDb:Float, ?maxDb:Float, ?minFreq:Float, ?maxFreq:Float):Array<Float>
		return inline getLevelsFromFrequencies(__frequencies = getFrequencies(startPos, __frequencies), buffer.sampleRate, barCount, levels, delta, minDb, maxDb, minFreq, maxFreq);

	/**
	 * Gets frequencies from an attached FlxSound from startPos.
	 * @param startPos Start Position to get from sound in milliseconds.
	 * @param frequencies The output for getting the frequencies, to avoid memory leaks (Optional).
	 * @return Output of frequencies
	 */
	public function getFrequencies(startPos:Float, ?frequencies:Array<Float>):Array<Float> {
		// https://github.com/FunkinCrew/grig.audio/commit/8567c4dad34cfeaf2ff23fe12c3796f5db80685e
		inline function butterfly4PointOptimized(i0:Int, i1:Int, i2:Int, i3:Int, w1_idx:Int, w2_idx:Int, w3_idx:Int) {
			// Load input values
			var x0r = __freqReals[i0];
			var x0i = __freqImags[i0];

			// Apply twiddle factors to x1, x2, x3
			// x1 = workingData[i1] * twiddle1
			var x1r_raw = __freqReals[i1];
			var x1i_raw = __freqImags[i1];
			var tw1r = __twiddleReals[w1_idx];
			var tw1i = __twiddleImags[w1_idx];
			var x1r = x1r_raw * tw1r - x1i_raw * tw1i;
			var x1i = x1r_raw * tw1i + x1i_raw * tw1r;

			// x2 = workingData[i2] * twiddle2
			var x2r_raw = __freqReals[i2];
			var x2i_raw = __freqImags[i2];
			var tw2r = __twiddleReals[w2_idx];
			var tw2i = __twiddleImags[w2_idx];
			var x2r = x2r_raw * tw2r - x2i_raw * tw2i;
			var x2i = x2r_raw * tw2i + x2i_raw * tw2r;

			// x3 = workingData[i3] * twiddle3
			var x3r_raw = __freqReals[i3];
			var x3i_raw = __freqImags[i3];
			var tw3r = __twiddleReals[w3_idx];
			var tw3i = __twiddleImags[w3_idx];
			var x3r = x3r_raw * tw3r - x3i_raw * tw3i;
			var x3i = x3r_raw * tw3i + x3i_raw * tw3r;

			// Compute intermediate values for 4-point DFT
			var t0r = x0r + x2r;  // (x0 + x2).real
			var t0i = x0i + x2i;  // (x0 + x2).imag
			var t1r = x0r - x2r;  // (x0 - x2).real
			var t1i = x0i - x2i;  // (x0 - x2).imag
			var t2r = x1r + x3r;  // (x1 + x3).real
			var t2i = x1i + x3i;  // (x1 + x3).imag
			var t3r = x1r - x3r;  // (x1 - x3).real
			var t3i = x1i - x3i;  // (x1 - x3).imag

			// Apply j multiplication: j * (a + jb) = -b + ja
			var jt3r = -t3i;  // j * t3.real = -t3.imag
			var jt3i = t3r;   // j * t3.imag = t3.real

			// Final 4-point DFT butterfly outputs
			__freqReals[i0] = t0r + t2r;        // X[k]
			__freqImags[i0] = t0i + t2i;
			__freqReals[i1] = t1r - jt3r;       // X[k + N/4]
			__freqImags[i1] = t1i - jt3i;
			__freqReals[i2] = t0r - t2r;        // X[k + N/2]
			__freqImags[i2] = t0i - t2i;
			__freqReals[i3] = t1r + jt3r;       // X[k + 3N/4]
			__freqImags[i3] = t1i + jt3i;
		}

		inline function butterfly2PointOptimized(i0:Int, i1:Int, w_idx:Int) {
			var tempr = __freqReals[i1] * __twiddleReals[w_idx] - __freqImags[i1] * __twiddleImags[w_idx];
			var tempi = __freqReals[i1] * __twiddleImags[w_idx] + __freqImags[i1] * __twiddleReals[w_idx];
			__freqReals[i1] = __freqReals[i0] - tempr;
			__freqImags[i1] = __freqImags[i0] - tempi;
			__freqReals[i0] += tempr;
			__freqImags[i0] += tempi;
		}

		__freqSamples = getSamples(startPos, fftN, true, __freqSamples);

		if (frequencies == null) frequencies = [];
		frequencies.resize(__N2);

		if (fftN == 1) frequencies[0] = __freqSamples[0];
		else {
			var n;
			for (i in 0...fftN) {
				n = __reverseIndices[i];
				__freqReals[n] = __freqSamples[i] * __windows[i];
				__freqImags[n] = 0;
			}

			var size = 1, s2, start, t;
			for (radix in __factors) {
				n = Math.floor(fftN / (size *= radix));
				s2 = size >> (radix >> 1);
				if (radix == 4) for (i in 0...n) {
					start = i * size;
					for (k in 0...s2)
						butterfly4PointOptimized(t = start + k, t = (t + s2), t = (t + s2), t = (t + s2),
							(k * n) % fftN, (2 * k * n) % fftN, (3 * k * n) % fftN);
				}
				else for (i in 0...n) {
					start = i * size;
					for (k in 0...s2) butterfly2PointOptimized(t = start + k, t = (t + s2), (k * n) % fftN);
				}
			}

			var inv = 1.0 / fftN;
			frequencies[0] = Math.sqrt(__freqReals[0] * __freqReals[0] + __freqImags[0] * __freqImags[0]) * inv;
			for (i in 1...__N2) frequencies[i] = 2 * Math.sqrt(__freqReals[i] * __freqReals[i] + __freqImags[i] * __freqImags[i]) * inv;
		}

		return frequencies;
	}

	/**
	 * Analyzes an attached FlxSound from startPos to endPos in milliseconds to get the amplitudes.
	 * @param startPos Start Position to get from sound in milliseconds.
	 * @param endPos End Position to get from sound in milliseconds.
	 * @param outOrOutMin The output minimum value from the analyzer, indices is in channels (0 to -0.5 -> 0 to 0.5) (Optional, if outMax doesn't get passed in, it will be [min, max] with all channels combined instead).
	 * @param outMax The output maximum value from the analyzer, indices is in channels (Optional).
	 * @return Output of amplitude from given position.
	 */
	public function analyze(startPos:Float, endPos:Float, ?outOrOutMin:Array<Float>, ?outMax:Array<Float>):Float {
		var hasOut = outOrOutMin != null;
		var hasTwoOut = hasOut && outMax != null;

		if (hasTwoOut) for (i in 0...buffer.channels) __min[i] = __max[i] = 0;
		__minByte = __maxByte = 0;

		__check();
		__read(startPos, endPos, hasTwoOut ? __analyzeCallback : __analyzeCallbackSimple);

		if (hasOut) {
			var f:Float;
			if (hasTwoOut) for (i in 0...buffer.channels) {
				if (outOrOutMin[i] < (f = __min[i] / byteSize)) outOrOutMin[i] = f;
				if (outMax[i] < (f = __max[i] / byteSize)) outMax[i] = f;
			}
			else {
				outOrOutMin.resize(2);
				if (outOrOutMin[0] < (f = __minByte / byteSize)) outOrOutMin[0] = f;
				if (outOrOutMin[1] < (f = __maxByte / byteSize)) outOrOutMin[1] = f;
			}
		}

		return (__maxByte + __minByte) / byteSize;
	}

	function __analyzeCallback(b:Int, c:Int):Void
		((b > __max[c]) ? (if ((__max[c] = b) > __maxByte) (__maxByte = b)) : (if (-b > __min[c]) (if ((__min[c] = -b) > __minByte) (__minByte = __min[c]))));

	function __analyzeCallbackSimple(b:Int, c:Int):Void
		((b > __maxByte) ? (__maxByte = b) : (if (-b > __minByte) (__minByte = -b)));

	/**
	 * Gets samples from startPos with given length of samples.
	 * @param startPos Start Position to get from sound in milliseconds.
	 * @param length Length of Samples.
	 * @param mono Merge all of the byte channels of samples in one channel instead (Optional).
	 * @param Output that gets passed into this function (Optional).
	 * @return Output of 
	 */
	public function getSamples(startPos:Float, length:Int, mono = true, ?output:Array<Float>):Array<Float> {
		((output == null) ? (__sampleOutput = output = []) : (__sampleOutput = output)).resize(__sampleOutputLength = length * (mono ? 1 : buffer.channels));
		__sampleIndex = 0;

		__check();
		__read(startPos, startPos + (length / __toBits * buffer.channels), mono ? __getSamplesCallbackMerge : __getSamplesCallback);

		__sampleOutput = null;
		return output;
	}

	function __getSamplesCallbackMerge(b:Int, c:Int):Void if (__sampleIndex < __sampleOutputLength) {
		if (c == 0) __sampleOutput[__sampleIndex] = b / buffer.channels / byteSize;
		else if (c == buffer.channels) {
			__sampleOutput[__sampleIndex] += b / buffer.channels / byteSize;
			__sampleIndex++;
		}
		else
			__sampleOutput[__sampleIndex] += b / buffer.channels / byteSize;
	}

	function __getSamplesCallback(b:Int, c:Int):Void if (__sampleIndex < __sampleOutputLength) {
		__sampleOutput[__sampleIndex] = b / byteSize;
		__sampleIndex++;
	}

	/**
	 * Read an attached FlxSound from startPos to endPos in milliseconds with a callback.
	 * @param startPos Start Position to get from sound in milliseconds.
	 * @param endPos End Position to get from sound in milliseconds.
	 * @param callback Int->Int->Void Byte->Channels->Void Callback to get the byte of a sample.
	 */
	public function read(startPos:Float, endPos:Float, callback:AudioAnalyzerCallback) {
		__check();
		__read(startPos, endPos, callback);
	}

	inline function __read(startPos:Float, endPos:Float, callback:AudioAnalyzerCallback) {
		if (buffer.data != null) __readData(startPos, endPos, callback);
		#if lime_cffi
		else if (__canReadStream() && (startPos += __readStream(startPos, endPos, callback)) >= endPos) {}
		#if lime_vorbis
		else if (__prepareDecoder()) __readDecoder(startPos, endPos, callback);
		#end
		#end
	}

	inline function __readData(startPos:Float, endPos:Float, callback:AudioAnalyzerCallback) {
		var pos = Math.floor(startPos * __toBits), end = Math.floor(endPos * __toBits), c = 0;
		pos -= pos % __sampleSize;
		end -= end % __sampleSize;

		while (pos < end) {
			callback(getByte(buffer.data.buffer, pos, __wordSize), c);
			if (++c > buffer.channels) c = 0;
			pos += __wordSize;
		}
	}

	#if lime_cffi
	inline function __canReadStream():Bool
		@:privateAccess return sound._source != null && sound._source.__backend != null && sound._source.__backend.playing;

	inline function __readStream(startPos:Float, endPos:Float, callback:AudioAnalyzerCallback):Float @:privateAccess {
		var backend = sound._source.__backend;
		var i = backend.bufferSizes.length - backend.queuedBuffers;
		var time = backend.bufferTimes[i] * 1000;

		var n = Math.floor((endPos - startPos) * __toBits);
		if (startPos >= time && startPos < backend.bufferTimes[backend.bufferSizes.length - 1] * 1000) {
			var pos = Math.floor((startPos - time) * __toBits), buf = backend.bufferDatas[i].buffer, size = backend.bufferSizes[i], c = 0;
			while (pos > size) {
				if (++i >= backend.bufferSizes.length) {
					n = 0;
					break;
				}
				pos -= size;
				buf = backend.bufferDatas[i].buffer;
				size = backend.bufferSizes[i];
			}
			pos -= pos % __sampleSize;

			while (n > 0) {
				callback(getByte(buf, pos, __wordSize), c);
				if (++c > buffer.channels) c = 0;
				if ((pos += __wordSize) >= size) {
					if (++i >= backend.bufferSizes.length) break;
					pos = 0;
					buf = backend.bufferDatas[i].buffer;
					size = backend.bufferSizes[i];
				}
				n -= __wordSize;
			}
		}

		return endPos - (n / __toBits);
	}

	#if lime_vorbis
	inline function __prepareDecoder():Bool @:privateAccess {
		if (buffer.__srcVorbisFile == null) return __vorbis != null;
		if (__vorbis != null) return true;
		if ((__vorbis = buffer.__srcVorbisFile.clone()) != null) { // IM HOPING IT HAVE A GC CLOSURE.
			__buffer = new ArrayBuffer(__bufferSize = (buffer.sampleRate >> 1) * __sampleSize); // 0.5 seconds of buffers.
			return true;
		}
		return false;
	}

	inline function __readDecoder(startPos:Float, endPos:Float, callback:AudioAnalyzerCallback) {
		var n = Math.floor((endPos - startPos) * __toBits);
		if ((n -= n % __sampleSize) > 0) {
			var pos = Math.floor((startPos - __bufferTime * 1000) * __toBits);
			pos -= pos % __sampleSize;

			var doRead = __bufferLastSize == 0 || (pos < 0 && pos >= __bufferSize);
			if (doRead) {
				if (startPos < 1) {
					__vorbis.rawSeek(0);
					__bufferTime = 0;
				}
				else
					__vorbis.timeSeek(__bufferTime = startPos / 1000);

				__bufferLastSize = pos = 0;
			}

			var isBigEndian = lime.system.System.endianness == lime.system.Endian.BIG_ENDIAN, ranOut = false, c = 0, result;
			while (true) {
				if (doRead) {
					result = __vorbis.read(__buffer, pos, __bufferSize - pos, isBigEndian, __wordSize, true);
					if (result == Vorbis.HOLE) continue;
					else if (result < 0) break;
					else if (!(ranOut = result == 0)) {
						__bufferLastTime = __vorbis.timeTell();
						__bufferLastSize += result;
						while (pos < __bufferLastSize) {
							callback(getByte(__buffer, pos, __wordSize), c);
							if (++c > buffer.channels) c = 0;
							pos += __wordSize;
							if ((n -= __wordSize) <= 0) break;
						}
					}
				}
				else {
					while (pos < __bufferLastSize) {
						callback(getByte(__buffer, pos, __wordSize), c);
						if (++c > buffer.channels) c = 0;
						pos += __wordSize;
						if ((n -= __wordSize) <= 0) break;
					}
					doRead = true;
					ranOut = pos >= __bufferSize;
				}

				if (n <= 0) break;
				else if (doRead && ranOut) {
					__bufferLastSize = pos = 0;
					__bufferTime = __bufferLastTime;
				}
			}
		}
	}
	#end
	#end
}