// 选词解释与单文摘要（T034；架构 4.2「选词仅发送选区和最少上下文」「译文与原文按段落关联，
// 原文始终保留」、SET-037/061/064）。
//
// 这一层只做三件事，且刻意**不**做界面判断：
//   1) 把选区 + 最少上下文（[SelectionExplanationRequest]，T020 的纯函数）拼成一次请求；
//   2) 把文章正文按 SET-061 的 8000 字符预算截断（超长**标注**截断，不静默丢）；
//   3) 把结果与失败情况如实交回（不伪造摘要、不覆盖源摘要）。
//
// 为什么复用 T020 的 SelectionExplanationRequest 而不是重写一份截断规则：那条规则是数据出境
// 边界（「只发送选区和最少上下文」），写两份必然漂移，而漂移的后果是「设置页说只发 1200 字、
// 实际发了整篇」。
library;

import 'package:flux/core/core.dart';

import 'package:flux/features/ai/application/ai_task_runner.dart';
import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/articles/application/article_text_actions.dart';

/// 一次「选词解释」的产出。
final class SelectionExplainOutcome {
  /// 构造产出。
  const SelectionExplainOutcome({
    this.text,
    this.error,
    this.contextTruncated = false,
    this.sentCharacters = 0,
  });

  /// 解释文本；失败时为 null。
  final String? text;

  /// 失败原因。
  final AppError? error;

  /// 是否发生过上下文截断（界面据此说明）。
  final bool contextTruncated;

  /// 实际发送的字符数（界面「将发送什么」用）。
  final int sentCharacters;

  /// 是否成功。
  bool get ok => text != null && text!.isNotEmpty;
}

/// 选词解释（单任务）。
///
/// **不改动文章的任何字段**：解释是只读动作，取消与失败都不会让正文发生变化（架构 4.2）。
final class SelectionExplainService {
  /// 构造服务。
  const SelectionExplainService({required this.runner, required this.clock});

  /// 任务队列（预算、五次规则、故障转移都在它里面）。
  final AiTaskRunner runner;

  /// 时钟。
  final Clock clock;

  /// 解释一段选区。
  ///
  /// [cancellation] 是取消信号：取消后不再发出任何请求，且**不改原文**。
  Future<SelectionExplainOutcome> explain({
    required String taskId,
    required String plainText,
    required String selection,
    required List<AiModel> models,
    int maxContextCharacters = kSelectionContextCharacters,
    AiCancellation? cancellation,
  }) async {
    final SelectionExplanationInput input = buildSelectionExplanationInput(
      plainText: plainText,
      selection: selection,
      maxContextCharacters: maxContextCharacters,
    );
    if (input.selection.isEmpty) {
      // 空选区：调用方不该发请求（也不会扣费）。
      return const SelectionExplainOutcome();
    }
    if (models.isEmpty) {
      return SelectionExplainOutcome(
        error: ProviderError(
          provider: '-',
          kind: 'noEnabledModel',
          detail: '没有可用的启用模型',
        ),
      );
    }
    final AiTaskOutcome outcome = await runner.run(
      taskId: taskId,
      request: AiRequest(
        modelId: models.first.modelId,
        messages: <AiMessage>[
          const AiMessage.system(kSelectionExplainPrompt),
          AiMessage.user(buildSelectionExplainUserMessage(input)),
        ],
        cancellation: cancellation,
      ),
      models: models,
    );
    final bool ok =
        (outcome.status == TaskStatus.succeeded ||
            outcome.status == TaskStatus.partial) &&
        outcome.hasResult;
    return SelectionExplainOutcome(
      text: ok ? outcome.text : null,
      error: ok ? null : outcome.error,
      contextTruncated: input.contextTruncated,
      sentCharacters: input.payload.length,
    );
  }
}

/// 一次「单文摘要」的产出。
final class ArticleSummaryOutcome {
  /// 构造产出。
  const ArticleSummaryOutcome({
    this.summary,
    this.error,
    this.truncated = false,
    this.skippedReason,
  });

  /// 生成的摘要（已带元数据）；失败或被跳过时为 null。
  final AiSummaryRecord? summary;

  /// 失败原因。
  final AppError? error;

  /// 正文是否被截断（SET-061）。
  final bool truncated;

  /// 跳过原因（没有正文 / 没有模型）；null 表示正常执行。
  final String? skippedReason;

  /// 是否成功产出摘要。
  bool get ok => summary != null;
}

/// 单文摘要（正文按 SET-061 截断，结果写 ai_summary，**不覆盖源摘要**）。
final class ArticleSummaryService {
  /// 构造服务。
  const ArticleSummaryService({
    required this.runner,
    required this.clock,
    this.charBudget = kSingleMaterialCharBudget,
  });

  /// 任务队列。
  final AiTaskRunner runner;

  /// 时钟（摘要的生成时刻）。
  final Clock clock;

  /// 单材料预算（SET-061）。
  final int charBudget;

  /// 为一篇正文生成摘要。
  ///
  /// 返回的 [ArticleSummaryOutcome.summary] 由调用方落库（本服务**不写库**）：把 IO 与
  /// 生成分开，让「什么时候写、写哪一列」只有仓储那一份实现。
  Future<ArticleSummaryOutcome> summarize({
    required String taskId,
    required String? body,
    required List<AiModel> models,
    AiCancellation? cancellation,
  }) async {
    final SummaryBody prepared = prepareSummaryBody(body, budget: charBudget);
    if (prepared.isEmpty) {
      return const ArticleSummaryOutcome(skippedReason: 'noBody');
    }
    if (models.isEmpty) {
      return ArticleSummaryOutcome(
        error: ProviderError(
          provider: '-',
          kind: 'noEnabledModel',
          detail: '没有可用的启用模型',
        ),
        truncated: prepared.truncated,
      );
    }
    final AiTaskOutcome outcome = await runner.run(
      taskId: taskId,
      request: AiRequest(
        modelId: models.first.modelId,
        messages: <AiMessage>[
          const AiMessage.system(kArticleSummaryPrompt),
          AiMessage.user(buildSummaryUserMessage(prepared)),
        ],
        cancellation: cancellation,
      ),
      models: models,
    );
    final bool ok =
        (outcome.status == TaskStatus.succeeded ||
            outcome.status == TaskStatus.partial) &&
        outcome.hasResult;
    if (!ok) {
      return ArticleSummaryOutcome(
        error: outcome.error,
        truncated: prepared.truncated,
      );
    }
    return ArticleSummaryOutcome(
      summary: AiSummaryRecord(
        text: outcome.text!,
        generatedAt: clock.now(),
        modelLabel: outcome.alias == null
            ? null
            : '${outcome.alias}/${outcome.modelId ?? ''}',
      ),
      truncated: prepared.truncated,
    );
  }
}

/// 一次「选词解释」的输入（纯数据）。
final class SelectionExplanationInput {
  /// 构造输入。
  const SelectionExplanationInput({
    required this.selection,
    required this.contextBefore,
    required this.contextAfter,
  });

  /// 用户选中的文本（原样，不截断）。
  final String selection;

  /// 选区之前的上下文（可能以省略号开头）。
  final String contextBefore;

  /// 选区之后的上下文（可能以省略号结尾）。
  final String contextAfter;

  /// 实际发送出去的正文部分（供界面「将发送什么」预览）。
  String get payload => '$contextBefore$selection$contextAfter';

  /// 是否两端上下文都被截断过（界面可据此说明「已截断」）。
  bool get contextTruncated =>
      contextBefore.startsWith(kContextEllipsis) ||
      contextAfter.endsWith(kContextEllipsis);
}

/// 上下文截断标记（与 T020 的实现同一个字符）。
const String kContextEllipsis = '…';

/// 选词解释的最小上下文上限（SET 未单独编号；T020 定为 1200 字，架构 4.2「最少上下文」）。
const int kSelectionContextCharacters = 1200;

/// 从整篇正文与选区构造一次解释输入。
///
/// 直接复用 T020 的纯函数：找不到选区位置时**不猜**（宁可没有上下文，也不要把正文另一处
/// 当成上下文发出去）。
SelectionExplanationInput buildSelectionExplanationInput({
  required String plainText,
  required String selection,
  int maxContextCharacters = kSelectionContextCharacters,
}) {
  final SelectionExplanationRequest request =
      SelectionExplanationRequest.fromDocument(
        plainText: plainText,
        selection: selection,
        maxContextCharacters: maxContextCharacters,
      );
  return SelectionExplanationInput(
    selection: request.selection,
    contextBefore: request.contextBefore,
    contextAfter: request.contextAfter,
  );
}

/// 单材料正文预算（SET-061：默认 8000 字符）。
const int kSingleMaterialCharBudget = 8000;

/// 一次单文摘要的正文准备结果。
final class SummaryBody {
  /// 构造结果。
  const SummaryBody({
    required this.text,
    required this.originalLength,
    required this.truncated,
  });

  /// 实际要发送的正文（已按预算截断）。
  final String text;

  /// 截断前的字符数。
  final int originalLength;

  /// 是否发生过截断。
  final bool truncated;

  /// 是否为空（调用方据此直接给「没有正文可总结」）。
  bool get isEmpty => text.trim().isEmpty;
}

/// 按 SET-061 准备摘要用的正文。
///
/// 在**字符边界**处截断，并在结果里记下「截过」。超长文章不做分块多次调用：SET-061 允许
/// 「长文分块或标截断」，而分块会让一次摘要变成 N 次计费调用（用户点一次「摘要」不该产生
/// 不可预期的费用），因此本轮选「标截断」。
SummaryBody prepareSummaryBody(
  String? body, {
  int budget = kSingleMaterialCharBudget,
}) {
  final String text = body ?? '';
  final List<int> runes = text.runes.toList(growable: false);
  if (budget <= 0 || runes.length <= budget) {
    return SummaryBody(
      text: text,
      originalLength: runes.length,
      truncated: false,
    );
  }
  return SummaryBody(
    text: String.fromCharCodes(runes.take(budget)),
    originalLength: runes.length,
    truncated: true,
  );
}

/// 单文摘要的提示词（要求不引入材料之外的信息）。
const String kArticleSummaryPrompt =
    '请用三到五句话概括下面这篇文章的要点。只依据文章内容，不要补充你已知的背景，'
    '不要评论，也不要编造文章没有提到的数字或人名。直接给出摘要正文。';

/// 选词解释的提示词。
const String kSelectionExplainPrompt =
    '请解释下面这段选中的文字在这篇文章语境里的意思，用两三句话。'
    '只依据给出的上下文，不要引入你已知的外部背景。直接给出解释。';

/// 拼装一次单文摘要的用户消息（含截断说明）。
String buildSummaryUserMessage(SummaryBody body) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('文章正文如下：')
    ..writeln(body.text);
  if (body.truncated) {
    // 截断必须**说出来**：不说的话模型会把半篇当全文总结，而用户看到的结论没有任何
    // 线索指向「材料本来就不全」（与 T032 的 fetchPage 回填同一条纪律）。
    buffer.writeln(
      '（正文已截断：原文 ${body.originalLength} 字符，此处仅 ${body.text.length} 字符。'
      '请不要据此断言文章没提及其它内容。）',
    );
  }
  return buffer.toString();
}

/// 拼装一次选词解释的用户消息（送出的就是 [SelectionExplanationInput.payload]）。
String buildSelectionExplainUserMessage(SelectionExplanationInput input) =>
    '上下文与选中文字：\n${input.payload}';
