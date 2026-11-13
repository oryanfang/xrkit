#import <Preferences/PSTableCell.h>

// 自己画的单行滑块单元格：
//   名称  ━━━━━━━○━━━━━━━━━━  数值
// 不继承系统的 PSSliderTableCell（它会自己重排子视图，跟我们的排版打架、挤成一团）。
//
// plist 里用：cell = PSStaticTextCell，cellClass = XRKSliderCell，
//            label、key、defaults、PostNotification、default、min、max 照常写，
//            xrkFormat = percent（0.4 → 40%）、signedPercent（-0.05 → -5%）或 seconds（3 → 3.0 秒），
//            xrkNameChars = 名称栏宽度（按几个汉字算，同一组写成一样的，滑块左端才对齐；不写就按自己名字的长度）
@interface XRKSliderCell : PSTableCell
@end
