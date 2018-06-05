//
//  ViewController.m
//  smerk_qr
//
//  Created by PHILIP SHEN on 5/25/18.
//  Copyright © 2018 PHILIP SHEN. All rights reserved.
//

#import "ViewController.h"
#import "SMKDetectionCamera.h"
#import <GPUImage/GPUImage.h>
#import <AVFoundation/AVFoundation.h>
#import "ImageViewController.h"
#import "ZBarSDK.h"

@interface ViewController ()

@property (nonatomic, strong) GPUImageView *cameraView;
@property (nonatomic, strong) SMKDetectionCamera *detector;

@property (nonatomic, assign) BOOL torchOn;
@property (nonatomic, assign) BOOL controlPanelVisible;

@property (strong, nonatomic) UIButton *torchButton;
@property (strong, nonatomic) UIButton *resetButton;
@property (strong, nonatomic) UIButton *filterButton;

@property (weak, nonatomic) IBOutlet UISlider *contrastSlider;
@property (weak, nonatomic) IBOutlet UISlider *brightnessSlider;
@property (weak, nonatomic) IBOutlet UISlider *exposureSlider;

@property (weak, nonatomic) IBOutlet UILabel *contrastLabel;
@property (weak, nonatomic) IBOutlet UILabel *brightnessLabel;
@property (weak, nonatomic) IBOutlet UILabel *exposureLabel;

@property (strong, nonatomic) GPUImageCropFilter *cropFilter;
@property (strong, nonatomic) GPUImageContrastFilter *contrastFilter;
@property (strong, nonatomic) GPUImageBrightnessFilter *brightnessFilter;
@property (strong, nonatomic) GPUImageExposureFilter *exposureFilter;

@property (strong, nonatomic) NSTimer *optimalScanTimer;
@property (strong, nonatomic) NSTimer *filteredScanTimer;

@property (strong, nonatomic) ZBarImageScanner *scanner;
@property (strong, nonatomic) GPUImageContrastFilter *screenshotContrastFilter;
@property (strong, nonatomic) GPUImageBrightnessFilter *screenshotBrightnessFilter;
@property (strong, nonatomic) GPUImageExposureFilter *screenshotExposureFilter;

@end

@implementation ViewController {
    CGFloat optimalContrast;
    CGFloat optimalBrightness;
    CGFloat optimalExposure;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    optimalContrast = 1.13;
    optimalBrightness = -0.55;
    optimalExposure = -0.7;
    
    [self initFilters];
    
    self.torchOn = NO;
    self.controlPanelVisible = NO;
    
    self.cameraView = [[GPUImageView alloc]  initWithFrame:UIScreen.mainScreen.bounds];
    
    self.detector = [[SMKDetectionCamera alloc] initWithSessionPreset:AVCaptureSessionPresetHigh cameraPosition:AVCaptureDevicePositionBack];
    [self.detector setOutputImageOrientation:UIInterfaceOrientationPortrait];
    self.cameraView.fillMode = kGPUImageFillModePreserveAspectRatio;
    
//    [self.detector beginDetecting:kMachineReadableMetaData codeTypes:@[AVMetadataObjectTypeQRCode] withDetectionBlock:^(SMKDetectionOptions detectionType, NSArray *detectedObjects, CGRect clapOrRectZero) {
//        if (detectionType & kMachineReadableMetaData) {
//            if ([detectedObjects.lastObject valueForKey:@"stringValue"]) {
//                [self showToast:[NSString stringWithFormat:@"NO FILTERS: ", [detectedObjects.lastObject valueForKey:@"stringValue"]];
//            }
//        }
//    }];
    
    CGSize buttonSize = CGSizeMake(100, 50);
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    
    self.torchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.torchButton.frame = CGRectMake(10, 20, buttonSize.width, buttonSize.height);
    [self.torchButton setTitle:@"Torch" forState:UIControlStateNormal];
    self.torchButton.backgroundColor = UIColor.whiteColor;
    [self.torchButton addTarget:self action:@selector(torchToggled) forControlEvents:UIControlEventTouchUpInside];
    
    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.resetButton.frame = CGRectMake(screenSize.width - (buttonSize.width+10), 20, buttonSize.width, buttonSize.height);
    [self.resetButton setTitle:@"Reset" forState:UIControlStateNormal];
    self.resetButton.backgroundColor = UIColor.whiteColor;
    [self.resetButton addTarget:self action:@selector(resetButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    
    self.filterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.filterButton.frame = CGRectMake(screenSize.width/2 - buttonSize.width/2, 20,
                                         buttonSize.width, buttonSize.height);
    [self.filterButton setTitle:@"Filters" forState:UIControlStateNormal];
    self.filterButton.backgroundColor = UIColor.whiteColor;
    [self.filterButton addTarget:self action:@selector(showControlPanel) forControlEvents:UIControlEventTouchUpInside];
    
    [self.detector addTarget:self.cropFilter];
    [self.cropFilter addTarget:self.contrastFilter];
    [self.contrastFilter addTarget:self.brightnessFilter];
    [self.brightnessFilter addTarget:self.exposureFilter];
    [self.exposureFilter addTarget:self.cameraView];
    
    [self.controlPanel setHidden:YES];
    
    [self.view addSubview:self.cameraView];
    [self.cameraView addSubview:self.resetButton];
    [self.cameraView addSubview:self.filterButton];
    [self.cameraView addSubview:self.torchButton];
    [self.view sendSubviewToBack:self.cameraView];
    [self.view bringSubviewToFront:self.controlPanel];
    [self updateLabels];
    
    [self.navigationController setNavigationBarHidden:YES];
    
    self.scanner = [[ZBarImageScanner alloc] init];
    [self.scanner setSymbology:0 config:ZBAR_CFG_ENABLE to:0];
    [self.scanner setSymbology:ZBAR_QRCODE config:ZBAR_CFG_ENABLE to:1];
    
    self.screenshotContrastFilter = [[GPUImageContrastFilter alloc] init];
    [self.screenshotContrastFilter setContrast:optimalContrast];
    self.screenshotBrightnessFilter = [[GPUImageBrightnessFilter alloc] init];
    [self.screenshotBrightnessFilter setBrightness:optimalBrightness];
    self.screenshotExposureFilter = [[GPUImageExposureFilter alloc] init];
    [self.screenshotExposureFilter setExposure:optimalExposure];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self.detector startCameraCapture];
    
    self.optimalScanTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [self.cropFilter useNextFrameForImageCapture];
        UIImage *image = [self.cropFilter imageFromCurrentFramebuffer];
        
        GPUImagePicture *inputImage = [[GPUImagePicture alloc] initWithImage:image];
        
        [inputImage addTarget:self.screenshotContrastFilter];
        [self.screenshotContrastFilter addTarget:self.screenshotBrightnessFilter];
        [self.screenshotBrightnessFilter addTarget:self.screenshotExposureFilter];
        
        [self.screenshotExposureFilter useNextFrameForImageCapture];
        [inputImage processImage];
        
        UIImage *outputImage = [self.screenshotExposureFilter imageFromCurrentFramebuffer];
        
        CGImageRef cgImage = [outputImage CGImage];
        
        ZBarImage *scanImage = [[ZBarImage alloc] initWithCGImage:cgImage];
        NSInteger count = [self.scanner scanImage:scanImage];
        
        if (count == 0) {return;}
        
        id<NSFastEnumeration> results = [self.scanner results];
        ZBarSymbol *symbol = nil;
        for (symbol in results) {
            NSString *code = symbol.data;
            [self showToast:[NSString stringWithFormat:@"OPTIMAL FILTERS: %@", code]];
        }
    }];
    
    self.filteredScanTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [self.exposureFilter useNextFrameForImageCapture];
        UIImage *image = [self.exposureFilter imageFromCurrentFramebuffer];
        
        CGImageRef cgImage = [image CGImage];
        ZBarImage *scanImage = [[ZBarImage alloc] initWithCGImage:cgImage];
        NSInteger count = [self.scanner scanImage:scanImage];
        
        if (count == 0) {return;}
        
        id<NSFastEnumeration> results = [self.scanner results];
        ZBarSymbol *symbol = nil;
        for (symbol in results) {
            NSString *code = symbol.data;
            [self showToast:[NSString stringWithFormat:@"CURRENT FILTERS: %@", code]];
        }
    }];
}

- (void) initFilters {
    self.cropFilter = [[GPUImageCropFilter alloc] init];
    [self.cropFilter setCropRegion:CGRectMake(0.25, 0.25, 0.5, 0.5)];
    
    self.contrastFilter = [[GPUImageContrastFilter alloc] init];
    [self.contrastFilter setContrast:[self.contrastSlider value]];
    
    self.brightnessFilter = [[GPUImageBrightnessFilter alloc] init];
    [self.brightnessFilter setBrightness:[self.brightnessSlider value]];
    
    self.exposureFilter = [[GPUImageExposureFilter alloc] init];
    [self.exposureFilter setExposure:[self.exposureSlider value]];
}

- (void) showToast:(NSString *)message {
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGSize toastSize = CGSizeMake(200, 80);
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(screen.width/2 - toastSize.width/2,
                                                               screen.height/2 - toastSize.width/2,
                                                               toastSize.width, toastSize.height)];
    [toast setText:message];
    [toast setTextColor:UIColor.whiteColor];
    [toast setBackgroundColor:[UIColor.blackColor colorWithAlphaComponent:0.6]];
    
    [self.view addSubview:toast];
    [self.view bringSubviewToFront:toast];
    
    [UIView animateWithDuration:2 animations:^{
        [toast setAlpha:0];
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

- (void) resetButtonPressed {
    [self.contrastSlider setValue:1];
    [self.contrastFilter setContrast:1];
    
    [self.brightnessSlider setValue:0];
    [self.brightnessFilter setBrightness:0];
    
    [self.exposureSlider setValue:0];
    [self.exposureFilter setExposure:0];
    
    [self updateLabels];
}

- (void) setFiltersToOptimal {
    [self.contrastSlider setValue:optimalContrast];
    [self.contrastFilter setContrast:optimalContrast];
    
    [self.brightnessSlider setValue:optimalBrightness];
    [self.brightnessFilter setBrightness:optimalBrightness];
    
    [self.exposureSlider setValue:optimalExposure];
    [self.exposureFilter setExposure:optimalExposure];
    
    [self updateLabels];
}

- (void) showControlPanel {
    [self.controlPanel setHidden:NO];
}

- (void) updateLabels {
    [self.contrastLabel setText:[NSString stringWithFormat:@"%f", [self.contrastSlider value]]];
    [self.brightnessLabel setText:[NSString stringWithFormat:@"%f", [self.brightnessSlider value]]];
    [self.exposureLabel setText:[NSString stringWithFormat:@"%f", [self.exposureSlider value]]];
}

- (void) torchToggled {
    Class captureDeviceClass = NSClassFromString(@"AVCaptureDevice");
    if (captureDeviceClass != nil) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch]) {
            [device lockForConfiguration:nil];
            
            if (self.torchOn) {
                [device setTorchMode:AVCaptureTorchModeOff];
            } else {
                [device setTorchModeOnWithLevel:0.8 error:nil];
                self.torchOn = YES;
            }
            
            [device unlockForConfiguration];
        }
    }
}

- (IBAction)closeButtonPressed:(id)sender {
    [self.controlPanel setHidden:YES];
    [self updateLabels];
}

- (IBAction)contrastChanged:(UISlider *)sender {
    [self.contrastFilter setContrast:sender.value];
    [self updateLabels];
}

- (IBAction)brightnessChanged:(UISlider *)sender {
    [self.brightnessFilter setBrightness:sender.value];
    [self updateLabels];
}

- (IBAction)exposureChanged:(UISlider *)sender {
    [self.exposureFilter setExposure:sender.value];
    [self updateLabels];
}

- (IBAction)optimalButtonPressed:(id)sender {
    [self setFiltersToOptimal];
}

@end
