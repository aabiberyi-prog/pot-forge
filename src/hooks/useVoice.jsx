import { useCallback } from 'react';
import { store } from '../utils/store';

let audioContext = new (window.AudioContext || window.webkitAudioContext)();
let source = null;
let gainNode = null;

function ensureGain() {
    if (!gainNode) {
        gainNode = audioContext.createGain();
        gainNode.connect(audioContext.destination);
    }
    return gainNode;
}

/** Apply playback volume 0–1 (also used while audio is playing). */
export async function setPlaybackVolume(volume) {
    const v = Math.max(0, Math.min(1, Number(volume)));
    const g = ensureGain();
    try {
        // Short ramp avoids clicks when adjusting mid-play
        const t = audioContext.currentTime;
        g.gain.cancelScheduledValues(t);
        g.gain.setValueAtTime(g.gain.value, t);
        g.gain.linearRampToValueAtTime(v, t + 0.03);
    } catch {
        g.gain.value = v;
    }
}

async function loadVolumeFromStore() {
    try {
        const v = await store.get('tts_volume');
        if (typeof v === 'number' && !Number.isNaN(v)) {
            return Math.max(0, Math.min(1, v));
        }
    } catch {
        /* ignore */
    }
    return 1;
}

export const useVoice = () => {
    const playOrStop = useCallback(async (data) => {
        if (source) {
            try {
                source.stop();
            } catch {
                /* already stopped */
            }
            try {
                source.disconnect();
            } catch {
                /* ignore */
            }
            source = null;
            return;
        }

        if (audioContext.state === 'suspended') {
            try {
                await audioContext.resume();
            } catch {
                /* ignore */
            }
        }

        const volume = await loadVolumeFromStore();
        const gain = ensureGain();
        gain.gain.value = volume;

        // Tauri TTS returns number[]; copy into a fresh ArrayBuffer for decodeAudioData
        const u8 = data instanceof Uint8Array ? data : new Uint8Array(data);
        const ab = u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);
        audioContext.decodeAudioData(
            ab,
            (buffer) => {
                if (source) {
                    try {
                        source.stop();
                        source.disconnect();
                    } catch {
                        /* ignore */
                    }
                }
                source = audioContext.createBufferSource();
                source.buffer = buffer;
                source.connect(gain);
                source.start();
                source.onended = () => {
                    try {
                        source.disconnect();
                    } catch {
                        /* ignore */
                    }
                    source = null;
                };
            },
            (err) => {
                console.error('decodeAudioData failed', err);
                source = null;
            }
        );
    }, []);

    return playOrStop;
};
