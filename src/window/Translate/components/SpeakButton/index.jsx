import { Button, Popover, PopoverTrigger, PopoverContent, Slider, Tooltip } from '@nextui-org/react';
import { HiOutlineVolumeUp, HiOutlineVolumeOff } from 'react-icons/hi';
import React, { useRef, useState, useCallback, useEffect } from 'react';
import { useTranslation } from 'react-i18next';

import { useConfig } from '../../../../hooks';
import { setPlaybackVolume } from '../../../../hooks/useVoice';

/**
 * Speak + volume control:
 * - Click: play / stop TTS
 * - Hover: show volume slider
 * - Volume 0 on slider: mute (no separate click-to-mute)
 */
export default function SpeakButton({ onSpeak, isDisabled = false }) {
    const { t } = useTranslation();
    const [ttsVolume, setTtsVolume] = useConfig('tts_volume', 1);
    const [open, setOpen] = useState(false);
    const leaveTimerRef = useRef(null);

    const clearLeaveTimer = () => {
        if (leaveTimerRef.current) {
            clearTimeout(leaveTimerRef.current);
            leaveTimerRef.current = null;
        }
    };

    const openSlider = useCallback(() => {
        if (isDisabled) return;
        clearLeaveTimer();
        setOpen(true);
    }, [isDisabled]);

    const scheduleClose = useCallback(() => {
        clearLeaveTimer();
        leaveTimerRef.current = setTimeout(() => {
            setOpen(false);
        }, 220);
    }, []);

    const applyVolume = useCallback(
        (v) => {
            const clamped = Math.max(0, Math.min(1, v));
            setTtsVolume(clamped);
            setPlaybackVolume(clamped);
        },
        [setTtsVolume]
    );

    useEffect(() => {
        return () => clearLeaveTimer();
    }, []);

    const volumePct = Math.round((ttsVolume ?? 1) * 100);
    const muted = (ttsVolume ?? 1) <= 0.001;

    return (
        <Popover
            isOpen={open}
            onOpenChange={setOpen}
            placement='top'
        >
            <PopoverTrigger>
                <div
                    className='inline-flex'
                    onMouseEnter={openSlider}
                    onMouseLeave={scheduleClose}
                >
                    <Tooltip
                        content={`${t('translate.speak')} · ${t('translate.tts_volume_hint')}`}
                        isDisabled={open}
                    >
                        <Button
                            isIconOnly
                            variant='light'
                            size='sm'
                            isDisabled={isDisabled}
                            onPress={() => {
                                if (isDisabled) return;
                                if (typeof onSpeak === 'function') {
                                    onSpeak();
                                }
                            }}
                        >
                            {muted ? (
                                <HiOutlineVolumeOff className='text-[16px]' />
                            ) : (
                                <HiOutlineVolumeUp className='text-[16px]' />
                            )}
                        </Button>
                    </Tooltip>
                </div>
            </PopoverTrigger>
            <PopoverContent
                className='w-[200px] p-3'
                onMouseEnter={openSlider}
                onMouseLeave={scheduleClose}
            >
                <div className='w-full flex flex-col gap-2'>
                    <div className='flex justify-between text-[12px] text-default-500'>
                        <span>{t('translate.tts_volume')}</span>
                        <span className='tabular-nums'>{muted ? t('translate.tts_muted') : `${volumePct}%`}</span>
                    </div>
                    <Slider
                        size='sm'
                        step={1}
                        minValue={0}
                        maxValue={100}
                        value={volumePct}
                        aria-label={t('translate.tts_volume')}
                        className='max-w-full'
                        onChange={(val) => {
                            const v = (Array.isArray(val) ? val[0] : val) / 100;
                            applyVolume(v);
                        }}
                    />
                    <p className='text-[10px] text-default-400 m-0'>{t('translate.tts_volume_hint')}</p>
                </div>
            </PopoverContent>
        </Popover>
    );
}
