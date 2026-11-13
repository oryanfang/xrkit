#import "XRKSliderCell.h"
#import "XRKLocalize.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>

@interface PSListController (XRKSliderCell)
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end

@implementation XRKSliderCell {
    UILabel *_nameLabel;
    UILabel *_valueLabel;
    UISlider *_slider;
    NSLayoutConstraint *_nameWidth;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier specifier:specifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    UIFont *body = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

    _nameLabel = [UILabel new];
    _nameLabel.font = body;
    _nameLabel.textColor = UIColor.labelColor;

    _valueLabel = [UILabel new];
    _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:body.pointSize weight:UIFontWeightRegular];
    _valueLabel.textColor = UIColor.secondaryLabelColor;
    _valueLabel.textAlignment = NSTextAlignmentRight;

    _slider = [UISlider new];
    // 拖动时只更新数字；松手才保存（避免拖动过程中不停通知 SpringBoard 刷新）
    [_slider addTarget:self action:@selector(xrk_sliderMoved) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(xrk_sliderReleased)
      forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    for (UIView *v in @[_nameLabel, _valueLabel, _slider]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:v];
    }
    // 数值栏按最长的数值定宽（比如「-15%」「10.0 秒」），数字变化时滑块不会跟着伸缩
    CGFloat valueWidth = ceil([[NSString stringWithFormat:XRKL(@"%.1f 秒"), 10.0] sizeWithAttributes:@{NSFontAttributeName: _valueLabel.font}].width) + 2;
    UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
    _nameWidth = [_nameLabel.widthAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [_nameLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [_nameLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        _nameWidth,
        [_slider.leadingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor constant:12],
        [_slider.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_valueLabel.leadingAnchor constraintEqualToAnchor:_slider.trailingAnchor constant:10],
        [_valueLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [_valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_valueLabel.widthAnchor constraintEqualToConstant:valueWidth],
    ]];

    [self xrk_loadFromSpecifier:specifier];
    return self;
}

// 用的是 PSStaticTextCell 类型，系统可能把它设成"不可用"（变灰、不能点），这里始终保持可用
- (void)setCellEnabled:(BOOL)enabled {
    [super setCellEnabled:YES];
    self.userInteractionEnabled = YES;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.textLabel.text = nil;   // 名称由自己的标签显示
    [self xrk_loadFromSpecifier:specifier];
}

- (void)xrk_loadFromSpecifier:(PSSpecifier *)specifier {
    if (!specifier) return;
    _nameLabel.text = specifier.name;
    self.textLabel.text = nil;

    // 名称栏宽度：按 xrkNameChars 个汉字算（同组对齐），没写就用自己名字的宽度
    NSDictionary *attrs = @{NSFontAttributeName: _nameLabel.font};
    NSUInteger chars = [[specifier propertyForKey:@"xrkNameChars"] unsignedIntegerValue];
    CGFloat own = [specifier.name ?: @"" sizeWithAttributes:attrs].width;
    CGFloat byChars = chars ? [[@"" stringByPaddingToLength:chars withString:@"国" startingAtIndex:0] sizeWithAttributes:attrs].width : 0;
    _nameWidth.constant = ceil(MAX(own, byChars));

    _slider.minimumValue = [[specifier propertyForKey:@"min"] floatValue];
    _slider.maximumValue = [[specifier propertyForKey:@"max"] floatValue] ?: 1;

    id value = nil;
    if ([specifier.target respondsToSelector:@selector(readPreferenceValue:)]) value = [specifier.target readPreferenceValue:specifier];
    if (!value) value = [specifier propertyForKey:@"default"];
    _slider.value = [value floatValue];
    [self xrk_updateValueLabel];
}

- (void)xrk_updateValueLabel {
    NSString *format = [self.specifier propertyForKey:@"xrkFormat"];
    float v = _slider.value;
    if ([format isEqualToString:@"percent"]) {
        _valueLabel.text = [NSString stringWithFormat:@"%.0f%%", v * 100];
    } else if ([format isEqualToString:@"signedPercent"]) {
        long p = lroundf(v * 100);
        _valueLabel.text = p > 0 ? [NSString stringWithFormat:@"+%ld%%", p] : [NSString stringWithFormat:@"%ld%%", p];
    } else if ([format isEqualToString:@"seconds"]) {
        _valueLabel.text = [NSString stringWithFormat:XRKL(@"%.1f 秒"), v];
    } else {
        _valueLabel.text = [NSString stringWithFormat:@"%.2f", v];
    }
}

- (void)xrk_sliderMoved {
    [self xrk_updateValueLabel];
}

// 存值取整：百分比到 1%、秒到 0.1 秒。滑块是连续的，不取整的话拖回「100%」实际存的可能是 0.996
- (float)xrk_roundedValue {
    NSString *format = [self.specifier propertyForKey:@"xrkFormat"];
    float step = [format isEqualToString:@"seconds"] ? 0.1f : 0.01f;
    float v = roundf(_slider.value / step) * step;
    return MAX(_slider.minimumValue, MIN(_slider.maximumValue, v));
}

- (void)xrk_sliderReleased {
    _slider.value = [self xrk_roundedValue];
    [self xrk_updateValueLabel];
    id target = self.specifier.target;
    if ([target respondsToSelector:@selector(setPreferenceValue:specifier:)]) {
        // 走 PSListController 的标准保存：写入 defaults 域并发 PostNotification
        [target setPreferenceValue:@(_slider.value) specifier:self.specifier];
    }
}

@end
