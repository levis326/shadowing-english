import 'package:common_learn_english/utils/chinese_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('半角标点转成中文全角标点', () {
    expect(
      normalizeChineseText('我在阿根廷北部吃过凯门鳄,而且很好吃.'),
      '我在阿根廷北部吃过凯门鳄，而且很好吃。',
    );
    expect(
      normalizeChineseText('真的吗?太好了!'),
      '真的吗？太好了！',
    );
    expect(
      normalizeChineseText('注意:先看这里;再看那里'),
      '注意：先看这里；再看那里',
    );
  });

  test('数字与英文缩写里的标点保持原样', () {
    expect(normalizeChineseText('价格是 1,000 元，约 3.5 折'), '价格是 1,000 元，约 3.5 折');
    expect(
      normalizeChineseText('vi. 组成, 存在于, 一致'),
      'vi. 组成，存在于，一致',
    );
    expect(normalizeChineseText('英文 Mr. Smith 来了'), '英文 Mr. Smith 来了');
  });

  test('去掉中文之间的空格与全角标点前的空格', () {
    expect(normalizeChineseText('我 在 学 英语'), '我在学英语');
    expect(normalizeChineseText('你好 ，世界 。'), '你好，世界。');
  });

  test('纯英文/纯数字文本不做改动', () {
    for (final String text in <String>[
      'Hello, world.',
      '1,000 items',
      'vi. be',
      '',
    ]) {
      expect(normalizeChineseText(text), text.trim());
    }
  });

  test('中英混排保留英文与中文之间的空格', () {
    expect(
      normalizeChineseText('我用 iPhone 听 BBC 六分钟英语'),
      '我用 iPhone 听 BBC 六分钟英语',
    );
  });
}
