//
//  AEAudioUnitChannel.m
//  TheAmazingAudioEngine
//
//  Created by Michael Tyson on 01/02/2013.
//  Copyright (c) 2013 A Tasty Pixel. All rights reserved.
//

#import "AEAudioUnitChannel.h"

#define checkResult(result,operation) (_checkResult((result),(operation),strrchr(__FILE__, '/')+1,__LINE__))
static inline BOOL _checkResult(OSStatus result, const char *operation, const char* file, int line) {
    if ( result != noErr ) {
        int fourCC = CFSwapInt32HostToBig(result);
        NSLog(@"%s:%d: %s result %d %08X %4.4s\n", file, line, operation, (int)result, (int)result, (char*)&fourCC);
        return NO;
    }
    return YES;
}

@interface AEAudioUnitChannel () {
    AUNode _node;
    AudioUnit _audioUnit;
    AUNode _converterNode;
    AudioUnit _converterUnit;
    AUGraph _audioGraph;
}
@end

@implementation AEAudioUnitChannel

- (id)initWithComponentDescription:(AudioComponentDescription)audioComponentDescription
                   audioController:(AEAudioController*)audioController
                             error:(NSError**)error {
    
    if ( !(self = [super init]) ) return nil;
    
    // Create the node, and the audio unit
    _audioGraph = audioController.audioGraph;
	OSStatus result;
    if ( !checkResult(result=AUGraphAddNode(_audioGraph, &audioComponentDescription, &_node), "AUGraphAddNode") ||
         !checkResult(result=AUGraphNodeInfo(_audioGraph, _node, NULL, &_audioUnit), "AUGraphNodeInfo") ) {
        
        if ( error ) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:result userInfo:[NSDictionary dictionaryWithObject:@"Couldn't initialise audio unit" forKey:NSLocalizedDescriptionKey]];
        [self release];
        return nil;
    }
    
    // Try to set the output audio description
    AudioStreamBasicDescription audioDescription = audioController.audioDescription;
    result = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &audioDescription, sizeof(AudioStreamBasicDescription));
    if ( result == kAudioUnitErr_FormatNotSupported ) {
        // The audio description isn't supported. Assign modified default audio description, and create an audio converter.
        AudioStreamBasicDescription defaultAudioDescription;
        UInt32 size = sizeof(defaultAudioDescription);
        result = AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &defaultAudioDescription, &size);
        defaultAudioDescription.mSampleRate = audioDescription.mSampleRate;
        AEAudioStreamBasicDescriptionSetChannelsPerFrame(&defaultAudioDescription, audioDescription.mChannelsPerFrame);
        checkResult(AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &defaultAudioDescription, size), "AudioUnitSetProperty");
        
        AudioComponentDescription audioConverterDescription = AEAudioComponentDescriptionMake(kAudioUnitManufacturer_Apple, kAudioUnitType_FormatConverter, kAudioUnitSubType_AUConverter);
        
        if ( !checkResult(result=AUGraphAddNode(_audioGraph, &audioConverterDescription, &_converterNode), "AUGraphAddNode") ||
             !checkResult(result=AUGraphNodeInfo(_audioGraph, _converterNode, NULL, &_converterUnit), "AUGraphNodeInfo") ||
             !checkResult(result=AUGraphConnectNodeInput(_audioGraph, _node, 0, _converterNode, 0), "AUGraphConnectNodeInput") ||
             !checkResult(result=AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &defaultAudioDescription, sizeof(AudioStreamBasicDescription)), "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)") ||
             !checkResult(result=AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &audioDescription, sizeof(AudioStreamBasicDescription)), "AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)") ) {
            
            if ( error ) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:result userInfo:[NSDictionary dictionaryWithObject:@"Couldn't setup converter audio unit" forKey:NSLocalizedDescriptionKey]];
            [self release];
            return nil;
        }
    }
    
    // Attempt to set the max frames per slice
    UInt32 maxFPS = 4096;
    AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, sizeof(maxFPS));
    
    if ( _converterUnit ) {
        AudioUnitSetProperty(_converterUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, sizeof(maxFPS));
    }
    
    checkResult(AUGraphUpdate(_audioGraph, NULL), "AUGraphUpdate");
    
    self.volume = 1.0;
    self.pan = 0.0;
    self.channelIsMuted = NO;
    self.channelIsPlaying = YES;
    
    return self;
}

-(void)dealloc {
    if ( _node ) {
        checkResult(AUGraphRemoveNode(_audioGraph, _node), "AUGraphRemoveNode");
    }
    if ( _converterNode ) {
        checkResult(AUGraphRemoveNode(_audioGraph, _converterNode), "AUGraphRemoveNode");
    }
    
    checkResult(AUGraphUpdate(_audioGraph, NULL), "AUGraphUpdate");
    
    [super dealloc];
}

-(AudioUnit)audioUnit {
    return _audioUnit;
}

static OSStatus renderCallback(id                        channel,
                               AEAudioController        *audioController,
                               const AudioTimeStamp     *time,
                               UInt32                    frames,
                               AudioBufferList          *audio) {
    AEAudioUnitChannel *THIS = (AEAudioUnitChannel*)channel;
    AudioUnitRenderActionFlags flags = 0;
    checkResult(AudioUnitRender(THIS->_converterUnit ? THIS->_converterUnit : THIS->_audioUnit, &flags, time, 0, frames, audio), "AudioUnitRender");
    return noErr;
}

-(AEAudioControllerRenderCallback)renderCallback {
    return renderCallback;
}

@end
