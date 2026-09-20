/// 中日韩字形回退顺序。
///
/// 应用只打包了拉丁字形的 Nunito，中文要靠系统字体渲染。如果只给一个
/// `fontFamily`（Nunito），Flutter 会走系统默认回退：在英文界面下常常挑到
/// 日文/繁体中文字体，于是「门、骨、直、画、厨」这类字形会不符合简体规范
/// （例如「门」的第一笔写成竖点、缺少规范的横折钩写法）。
///
/// 这里显式把**简体中文字体**排在前面：Windows 用微软雅黑，macOS 用苹方，
/// Linux/Android 用 Noto Sans CJK SC，都取不到时才交给系统兜底。
const List<String> kCjkFontFallback = <String>[
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Hiragino Sans GB',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Source Han Sans SC',
  'Source Han Sans CN',
  'WenQuanYi Micro Hei',
  'SimHei',
  'Heiti SC',
];

/// 中日韩文字排版的推荐字体大小缩放（中文方块字比拉丁字母视觉更满）。
const double kCjkFontScaleHint = 1;
