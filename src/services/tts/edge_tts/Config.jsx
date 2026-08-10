import { INSTANCE_NAME_CONFIG_KEY } from '../../../utils/service_instance';
import { Button, Input, Select, SelectItem } from '@nextui-org/react';
import toast, { Toaster } from 'react-hot-toast';
import { useTranslation } from 'react-i18next';
import React, { useState } from 'react';

import { useConfig } from '../../../hooks/useConfig';
import { useToastStyle } from '../../../hooks';
import { Language } from './index';
import { tts } from './index';

const ZH_VOICES = [
    { key: 'zh-CN-XiaoxiaoNeural', label: '晓晓 (少御向/温和)' },
    { key: 'zh-CN-XiaoyiNeural', label: '晓伊 (活泼)' },
    { key: 'zh-CN-YunxiNeural', label: '云希 (男声)' },
    { key: 'zh-CN-YunyangNeural', label: '云扬 (男声·新闻)' },
];

const EN_VOICES = [
    { key: 'en-US-AriaNeural', label: 'Aria (US female · mature professional)' },
    { key: 'en-US-MichelleNeural', label: 'Michelle (US female · news/prose)' },
    { key: 'en-US-JennyNeural', label: 'Jenny (US female · friendly)' },
    { key: 'en-US-AvaNeural', label: 'Ava (US female · soft)' },
    { key: 'en-US-EmmaNeural', label: 'Emma (US female · cheerful)' },
    { key: 'en-US-AndrewNeural', label: 'Andrew (US male)' },
];

export function Config(props) {
    const [isLoading, setIsLoading] = useState(false);
    const { instanceKey, updateServiceList, onClose } = props;
    const { t } = useTranslation();
    const [edgeConfig, setEdgeConfig] = useConfig(
        instanceKey,
        {
            [INSTANCE_NAME_CONFIG_KEY]: t('services.tts.edge_tts.title'),
            voice_zh: 'zh-CN-XiaoxiaoNeural',
            // Mature American professional woman (news/clear style)
            voice_en: 'en-US-AriaNeural',
            rate: '-20%',
            pitch: '+0Hz',
        },
        { sync: false }
    );

    const toastStyle = useToastStyle();

    return (
        edgeConfig !== null && (
            <>
                <Toaster />
                <div className='config-item'>
                    <Input
                        label={t('services.instance_name')}
                        labelPlacement='outside-left'
                        value={edgeConfig[INSTANCE_NAME_CONFIG_KEY]}
                        variant='bordered'
                        classNames={{
                            base: 'justify-between',
                            label: 'text-[length:--nextui-font-size-medium]',
                            mainWrapper: 'max-w-[50%]',
                        }}
                        onValueChange={(value) => {
                            setEdgeConfig({
                                ...edgeConfig,
                                [INSTANCE_NAME_CONFIG_KEY]: value,
                            });
                        }}
                    />
                </div>
                <div className='config-item'>
                    <h3 className='my-auto'>{t('services.tts.edge_tts.voice_zh')}</h3>
                    <Select
                        className='max-w-[50%]'
                        selectedKeys={[edgeConfig.voice_zh || 'zh-CN-XiaoxiaoNeural']}
                        onChange={(e) => {
                            setEdgeConfig({ ...edgeConfig, voice_zh: e.target.value });
                        }}
                    >
                        {ZH_VOICES.map((v) => (
                            <SelectItem key={v.key} value={v.key}>
                                {v.label}
                            </SelectItem>
                        ))}
                    </Select>
                </div>
                <div className='config-item'>
                    <h3 className='my-auto'>{t('services.tts.edge_tts.voice_en')}</h3>
                    <Select
                        className='max-w-[50%]'
                        selectedKeys={[edgeConfig.voice_en || 'en-US-AriaNeural']}
                        onChange={(e) => {
                            setEdgeConfig({ ...edgeConfig, voice_en: e.target.value });
                        }}
                    >
                        {EN_VOICES.map((v) => (
                            <SelectItem key={v.key} value={v.key}>
                                {v.label}
                            </SelectItem>
                        ))}
                    </Select>
                </div>
                <div className='config-item'>
                    <h3 className='my-auto'>{t('services.tts.edge_tts.rate')}</h3>
                    <Input
                        value={edgeConfig.rate || '-20%'}
                        variant='bordered'
                        className='max-w-[50%]'
                        placeholder='-20%'
                        onValueChange={(value) => {
                            setEdgeConfig({ ...edgeConfig, rate: value });
                        }}
                    />
                </div>
                <div className='config-item'>
                    <h3 className='my-auto'>{t('services.tts.edge_tts.pitch')}</h3>
                    <Input
                        value={edgeConfig.pitch || '+10Hz'}
                        variant='bordered'
                        className='max-w-[50%]'
                        placeholder='+10Hz'
                        onValueChange={(value) => {
                            setEdgeConfig({ ...edgeConfig, pitch: value });
                        }}
                    />
                </div>
                <div>
                    <Button
                        isLoading={isLoading}
                        fullWidth
                        color='primary'
                        onPress={() => {
                            setIsLoading(true);
                            tts('Hello, 你好', Language.en, { config: edgeConfig }).then(
                                () => {
                                    setIsLoading(false);
                                    setEdgeConfig(edgeConfig, true);
                                    updateServiceList(instanceKey);
                                    onClose();
                                },
                                (e) => {
                                    setIsLoading(false);
                                    toast.error(t('config.service.test_failed') + e.toString(), {
                                        style: toastStyle,
                                    });
                                }
                            );
                        }}
                    >
                        {t('common.save')}
                    </Button>
                </div>
            </>
        )
    );
}
