import wave
import math
import struct
import random

def generate_whoosh():
    # Generate a white noise sweep (lowpass filter sweeping up then down)
    framerate = 44100
    duration = 1.0 # seconds
    num_frames = int(framerate * duration)
    
    with wave.open('/Users/aliustaoglu/Developer/playground/flutter_tvos_engine_monorepo/release_video/public/whoosh.wav', 'w') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(framerate)
        
        # Simple noise with envelope
        for i in range(num_frames):
            t = i / framerate
            # envelope: rise fast, decay slow
            env = t * math.exp(-t * 5) * 10
            noise = random.uniform(-1, 1)
            # volume
            val = int(noise * env * 10000)
            if val > 32767: val = 32767
            if val < -32768: val = -32768
            f.writeframesraw(struct.pack('<h', val))

def generate_pop():
    # Generate a quick pop sound (sine wave rapidly decreasing in frequency and amplitude)
    framerate = 44100
    duration = 0.2
    num_frames = int(framerate * duration)
    
    with wave.open('/Users/aliustaoglu/Developer/playground/flutter_tvos_engine_monorepo/release_video/public/pop.wav', 'w') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(framerate)
        
        phase = 0
        for i in range(num_frames):
            t = i / framerate
            env = math.exp(-t * 30)
            freq = 400 * math.exp(-t * 20)
            phase += 2 * math.pi * freq / framerate
            
            val = int(math.sin(phase) * env * 15000)
            if val > 32767: val = 32767
            if val < -32768: val = -32768
            f.writeframesraw(struct.pack('<h', val))

def generate_crt_off():
    # Generate a CRT shutdown sound: a click followed by a fading whine
    framerate = 44100
    duration = 1.0
    num_frames = int(framerate * duration)
    
    with wave.open('/Users/aliustaoglu/Developer/playground/flutter_tvos_engine_monorepo/release_video/public/crt_off.wav', 'w') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(framerate)
        
        phase = 0
        for i in range(num_frames):
            t = i / framerate
            
            # 1. Initial click (fast decay pulse)
            click = math.exp(-t * 200) * math.sin(t * 1000)
            
            # 2. High pitch whine (descending freq)
            whine_env = math.exp(-t * 8) * (0.3 if t > 0.01 else 0)
            whine_freq = 15000 * math.exp(-t * 10)
            phase += 2 * math.pi * whine_freq / framerate
            whine = math.sin(phase) * whine_env
            
            # 3. Static/Noise (very quiet)
            noise = random.uniform(-1, 1) * math.exp(-t * 5) * 0.05
            
            val = int((click + whine + noise) * 15000)
            if val > 32767: val = 32767
            if val < -32768: val = -32768
            f.writeframesraw(struct.pack('<h', val))

def generate_static():
    # Generate a short burst of static white noise
    framerate = 44100
    duration = 1.0
    num_frames = int(framerate * duration)
    
    with wave.open('/Users/aliustaoglu/Developer/playground/flutter_tvos_engine_monorepo/release_video/public/static.wav', 'w') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(framerate)
        
        for i in range(num_frames):
            t = i / framerate
            # Envelope: quick fade in, stay, quick fade out
            env = 1.0
            if t < 0.05: env = t / 0.05
            if t > duration - 0.05: env = (duration - t) / 0.05
            
            noise = random.uniform(-1, 1)
            val = int(noise * env * 8000)
            if val > 32767: val = 32767
            if val < -32768: val = -32768
            f.writeframesraw(struct.pack('<h', val))

generate_whoosh()
generate_pop()
generate_crt_off()
generate_static()
