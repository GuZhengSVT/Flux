# Flux 渲染夹具：Markdown 与常用 LaTeX

> 用途：T004 固化的语法样本，供 T019/T020 的正文渲染与 T035 的翻译分段复用。
> 内容全部为虚构示例，不含真实文章。

## 1. 基础结构

普通段落，含 **粗体**、*斜体*、`行内代码`、[链接](https://example.com) 与 ~~删除线~~。

### 1.1 列表

1. 有序项一
2. 有序项二
   - 嵌套无序项
   - 另一项

### 1.2 引用层级

> 一级引用
>
> > 二级引用

### 1.3 表格

| 列一 | 列二 | 列三 |
| --- | :---: | ---: |
| a | b | c |
| 长文本单元格，用于验证列宽与横向滚动 | 中 | 1 |

### 1.4 围栏代码块

```dart
// 未知语言应回退为纯文本显示；这里用已知语言验证高亮与复制。
final Result<int> parsed = Ok<int>(42);
```

```text-unknown-language
这不是有效语言标识，应显示为纯文本而不是空白。
```

## 2. 行内数学 `$...$`

爱因斯坦质能方程 $E = mc^2$，其中 $m$ 为质量、$c$ 为光速。

希腊字母行内：$\alpha$、$\beta$、$\gamma$、$\theta$、$\lambda$、$\pi$、$\sigma$、$\Omega$。

上下标组合：$x_1^2 + x_2^2 = r^2$，以及 $a_{i,j}^{(k)}$。

## 3. 独立公式 `$$...$$`

分数与根式：

$$\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$

求和与积分：

$$\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}$$

$$\int_{0}^{\infty} e^{-x^2}\, dx = \frac{\sqrt{\pi}}{2}$$

括号伸缩（`\left` / `\right`）：

$$\left( \frac{a}{b} \right)^{n} \quad \left[ \frac{\partial f}{\partial x} \right]_{x=0}$$

矩阵：

$$\begin{pmatrix} a & b \\ c & d \end{pmatrix} \cdot \begin{pmatrix} x \\ y \end{pmatrix} = \begin{pmatrix} ax + by \\ cx + dy \end{pmatrix}$$

分段函数（cases）：

$$f(x) = \begin{cases} x^2 & x \ge 0 \\ -x^2 & x < 0 \end{cases}$$

对齐（align，多行 `&` 对齐）：

$$\begin{aligned} (a+b)^2 &= a^2 + 2ab + b^2 \\ (a-b)^2 &= a^2 - 2ab + b^2 \end{aligned}$$

## 4. 边界与回退

货币符号不应被当成数学：价格为 $19.99 与 $29.99，两者相差 $10.00。

转义美元：\$100 表示字面美元符号，不进入数学模式。

未闭合的行内公式应原样可见：这里写 $x + y 而没有结束符。

不支持的宏应显示原式并给出提示，而不是空白：$\notacommand{arg}$。

## 5. 长中文与中英混排

这是一段较长的中文段落，用来验证没有空格分词的情况下换行、对齐与行高是否正常；中间插入 English words and numbers 2026 以及标点，例如「中文引号」、（全角括号）与 emoji 🙂。连续超长词用于溢出测试：AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA。

## 6. 图片与危险链接

![虚构图片](https://example.com/media/fixture.png)

安全链接应可点击：[示例站](https://example.com/page)。

危险协议必须被拒绝渲染为可点击链接：[不要执行](javascript:alert(1))。

事件属性与脚本必须被剥离：<script>alert('xss')</script> 与 <img src="x" onerror="alert(1)">。
