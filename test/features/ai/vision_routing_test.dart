// T033：视觉路由、图像输入限制与三个协议的图像分量构造。
//
// 这一组用例盯的是架构 4.3 与 SET-034/065 的**可断言条文**：
//   - 路由顺序：专用视觉模型 → 有视觉能力的主模型 → 跳过（且跳过不是失败）；
//   - 指定了但不可用/没声明能力的模型**不**被绕过，而是回退并把原因带进结论；
//   - 单图 4 MiB / 最多 6 张：超单图的标降采样、超数量的标跳过（都不静默）；
//   - 三个协议的图像分量形状各异（CC 的 image_url 嵌套对象 / Responses 的 input_image
//     平铺字符串 / Anthropic 的 base64 源），各有断言且**不互相套用**；
//   - 没有视觉模型时文本链路继续（请求里一个图片分量都不带）。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flux/features/ai/domain/ai_message.dart';
import 'package:flux/features/ai/domain/ai_model.dart';
import 'package:flux/features/ai/domain/ai_protocol.dart';
import 'package:flux/features/ai/domain/ai_task_record.dart';
import 'package:flux/features/ai/domain/model_capability.dart';
import 'package:flux/features/ai/domain/vision_routing.dart';
import 'package:flux/infrastructure/network/ai_http.dart';

/// 构造一条模型记录。
AiModel model(
  String alias, {
  bool vision = false,
  AiProtocol protocol = AiProtocol.openAiChatCompletions,
}) => AiModel(
  alias: alias,
  protocol: protocol,
  baseUrl: 'https://$alias.example.com',
  modelId: '$alias-model',
  capability: ModelCapability(vision: vision),
);

/// 一张最小图片分量（字节内容不重要，形状才是断言对象）。
AiImagePart image({String mime = 'image/png', int bytes = 8}) => AiImagePart(
  bytes: Uint8List.fromList(List<int>.generate(bytes, (int i) => i)),
  mimeType: mime,
  width: 640,
  height: 480,
  sourceRef: 'img-page-1',
);

void main() {
  group('视觉路由顺序（SET-034 + 架构 4.3）', () {
    test('设置了专用视觉模型时优先用它（即使主模型也有视觉能力）', () {
      final VisionRoute route = selectVisionRoute(
        enabledModels: <AiModel>[
          model('main', vision: true),
          model('dedicated', vision: true),
        ],
        dedicatedAlias: 'dedicated',
      );
      expect(route, isA<VisionRouteDedicated>());
      expect((route as VisionRouteDedicated).model.alias, 'dedicated');
    });

    test('未设置专用模型时回退到第一个有视觉能力的主模型（跳过无视觉的）', () {
      final VisionRoute route = selectVisionRoute(
        enabledModels: <AiModel>[
          model('textOnly'),
          model('visionMain', vision: true),
          model('visionSecond', vision: true),
        ],
      );
      expect(route, isA<VisionRoutePrimary>());
      expect((route as VisionRoutePrimary).model.alias, 'visionMain');
    });

    test('一个视觉模型都没有时返回「跳过」而不是报错（文本链路继续）', () {
      final VisionRoute route = selectVisionRoute(
        enabledModels: <AiModel>[model('a'), model('b')],
      );
      expect(route, isA<VisionRouteSkip>());
      expect((route as VisionRouteSkip).reason, VisionSkipReason.noVisionModel);
    });

    test('专用模型不在启用列表里时回退，并把原因带进结论（不假装生效）', () {
      final VisionRoute route = selectVisionRoute(
        enabledModels: <AiModel>[model('main', vision: true)],
        dedicatedAlias: 'missing',
      );
      expect(route, isA<VisionRoutePrimary>());
      final VisionRoutePrimary primary = route as VisionRoutePrimary;
      expect(primary.model.alias, 'main');
      expect(primary.note, contains('missing'));
    });

    test('专用模型没声明视觉能力时不按名字猜（回退并说明），且没有视觉模型则跳过', () {
      final VisionRoute fallback = selectVisionRoute(
        enabledModels: <AiModel>[
          model('dedicated'),
          model('main', vision: true),
        ],
        dedicatedAlias: 'dedicated',
      );
      expect(fallback, isA<VisionRoutePrimary>());
      expect((fallback as VisionRoutePrimary).note, contains('未声明视觉能力'));

      final VisionRoute none = selectVisionRoute(
        enabledModels: <AiModel>[model('dedicated')],
        dedicatedAlias: 'dedicated',
      );
      expect(none, isA<VisionRouteSkip>());
      expect(
        (none as VisionRouteSkip).reason,
        VisionSkipReason.dedicatedModelLacksVision,
        reason: '跳过原因要说清「是专用模型配置不对」，而不是笼统的「没有视觉模型」',
      );
    });

    test('空别名按「未设置」处理（同步来的空串不该跳过主模型）', () {
      final VisionRoute route = selectVisionRoute(
        enabledModels: <AiModel>[model('main', vision: true)],
        dedicatedAlias: '   ',
      );
      expect(route, isA<VisionRoutePrimary>());
    });
  });

  group('图像输入限制（SET-065：开关 / 6 张 / 4 MiB）', () {
    ImageCandidateInfo candidate(String ref, {int? bytes}) =>
        ImageCandidateInfo(ref: ref, byteLength: bytes);

    test('超过 6 张时只取前 6 张，其余标 overCountLimit 且置 truncatedByCount', () {
      final ImageInputPlan plan = planImageInputs(
        candidates: <ImageCandidateInfo>[
          for (int i = 1; i <= 8; i++) candidate('img-$i'),
        ],
        limits: const ImageInputLimits(),
      );
      expect(plan.accepted, hasLength(6));
      expect(plan.truncatedByCount, isTrue);
      expect(
        plan.decisions
            .skip(6)
            .every(
              (ImageInputDecision d) =>
                  d.skipDetail == ImageInputSkip.overCountLimit,
            ),
        isTrue,
      );
    });

    test('已知字节数超过单图上限的标降采样；未知大小的不预先标', () {
      final ImageInputPlan plan = planImageInputs(
        candidates: <ImageCandidateInfo>[
          candidate('big', bytes: 5 * 1024 * 1024),
          candidate('small', bytes: 1024),
          candidate('unknown'),
        ],
        limits: const ImageInputLimits(),
      );
      expect(plan.accepted, hasLength(3));
      expect(plan.downsampleCount, 1);
      final ImageInputDecision big = plan.decisions.first;
      expect(big.downsample, isTrue, reason: '5 MiB 超过 SET-065 的 4 MiB');
      expect(plan.decisions[1].downsample, isFalse);
      expect(
        plan.decisions[2].downsample,
        isFalse,
        reason: '不知道大小时不预先标降采样（会让一批正常大小的图被无谓重编码）',
      );
    });

    test('开关关闭时全部跳过（原因 disabled），且不是错误', () {
      final ImageInputPlan plan = planImageInputs(
        candidates: <ImageCandidateInfo>[candidate('a'), candidate('b')],
        limits: const ImageInputLimits(enabled: false),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.truncatedByCount, isFalse);
      expect(
        plan.decisions.every(
          (ImageInputDecision d) => d.skipDetail == ImageInputSkip.disabled,
        ),
        isTrue,
      );
    });

    test('设置值结构不符时逐项回退注册表默认值（开关/数量/单图上限各自独立）', () {
      const ImageInputLimits fallback = ImageInputLimits();
      final ImageInputLimits fromEmpty = ImageInputLimits.fromSetting(null);
      expect(fromEmpty.enabled, fallback.enabled);
      expect(fromEmpty.maxImages, 6);
      expect(fromEmpty.maxImageMiB, 4);

      final ImageInputLimits partial = ImageInputLimits.fromSetting(
        <String, Object?>{'enabled': false, 'maxImages': 0, 'maxImageMiB': 'x'},
      );
      expect(partial.enabled, isFalse, reason: '写对的开关位要生效');
      expect(partial.maxImages, 6, reason: '数量为 0 会让功能永远什么都不做，回退默认值');
      expect(partial.maxImageMiB, 4, reason: '类型错的单图上限回退默认值');
    });

    test('maxImageBytes 是 MiB 换算（4 → 4 MiB）', () {
      expect(const ImageInputLimits().maxImageBytes, 4 * 1024 * 1024);
      expect(
        const ImageInputLimits(maxImageMiB: 2).maxImageBytes,
        2 * 1024 * 1024,
      );
    });
  });

  group('三协议的图像分量构造（形状各异，各有断言）', () {
    test('Chat Completions：content 变成分量数组，图片是 image_url 嵌套对象', () {
      final Map<String, Object?> body = chatCompletionsRequestBody(
        AiRequest(
          modelId: 'm',
          messages: <AiMessage>[
            AiMessage.user('看图', images: <AiImagePart>[image()]),
          ],
        ),
        'm',
      );
      final Map<String, Object?> message =
          (body['messages']! as List<Object?>).first! as Map<String, Object?>;
      final List<Object?> content = message['content']! as List<Object?>;
      expect(content, hasLength(2));
      final Map<String, Object?> text = content[0]! as Map<String, Object?>;
      expect(text['type'], 'text');
      expect(text['text'], '看图');
      final Map<String, Object?> imagePart =
          content[1]! as Map<String, Object?>;
      expect(imagePart['type'], 'image_url');
      final Map<String, Object?> url =
          imagePart['image_url']! as Map<String, Object?>;
      expect(url['url'], startsWith('data:image/png;base64,'));
    });

    test('Responses：分量类型是 input_image，image_url 是平铺字符串', () {
      final Map<String, Object?> body = responsesRequestBody(
        AiRequest(
          modelId: 'm',
          messages: <AiMessage>[
            AiMessage.user('看图', images: <AiImagePart>[image()]),
          ],
        ),
        'm',
      );
      final Map<String, Object?> item =
          (body['input']! as List<Object?>).first! as Map<String, Object?>;
      final List<Object?> content = item['content']! as List<Object?>;
      final Map<String, Object?> imagePart =
          content[1]! as Map<String, Object?>;
      expect(imagePart['type'], 'input_image');
      expect(
        imagePart['image_url'],
        isA<String>(),
        reason: 'Responses 的 image_url 是平铺字符串，不是 Chat Completions 的嵌套对象',
      );
      expect(imagePart['image_url'], startsWith('data:image/png;base64,'));
    });

    test('Anthropic：图片是 base64 源（type=base64 + media_type + data），不给 URL', () {
      final Map<String, Object?> body = anthropicMessagesRequestBody(
        AiRequest(
          modelId: 'm',
          messages: <AiMessage>[
            AiMessage.user(
              '看图',
              images: <AiImagePart>[image(mime: 'image/jpeg')],
            ),
          ],
        ),
        'm',
      );
      final Map<String, Object?> message =
          (body['messages']! as List<Object?>).first! as Map<String, Object?>;
      final List<Object?> content = message['content']! as List<Object?>;
      final Map<String, Object?> imagePart =
          content[1]! as Map<String, Object?>;
      expect(imagePart['type'], 'image');
      final Map<String, Object?> source =
          imagePart['source']! as Map<String, Object?>;
      expect(source['type'], 'base64');
      expect(source['media_type'], 'image/jpeg');
      expect(source['data'], isA<String>());
      expect(
        imagePart.containsKey('url'),
        isFalse,
        reason: 'Anthropic 不接受让服务商去远端取图',
      );
    });

    test('纯文本消息的 content 仍是字符串（图片来源只影响带图的消息）', () {
      final Map<String, Object?> body = chatCompletionsRequestBody(
        AiRequest(
          modelId: 'm',
          messages: <AiMessage>[const AiMessage.user('没有图')],
        ),
        'm',
      );
      final Map<String, Object?> message =
          (body['messages']! as List<Object?>).first! as Map<String, Object?>;
      expect(
        message['content'],
        isA<String>(),
        reason: '不带图时不该把 content 改成数组（会让一批既有夹具与实现无谓地变化）',
      );
    });

    test('dataUrl 与 base64Data 与字节一致（换算无误）', () {
      final AiImagePart part = AiImagePart(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        mimeType: 'image/png',
        width: 1,
        height: 1,
      );
      expect(part.base64Data, 'AQID');
      expect(part.dataUrl, 'data:image/png;base64,AQID');
      expect(part.digest, isNotEmpty);
    });
  });

  group('图像进入输入快照（缓存键的判据）', () {
    test('同一段文字带不带图得到不同的输入哈希与缓存键', () {
      final AiInputSnapshot without = AiInputSnapshot.fromRequest(
        AiRequest(
          modelId: 'm',
          messages: <AiMessage>[const AiMessage.user('同一段文字')],
        ),
      );
      final AiInputSnapshot withImage = AiInputSnapshot.fromRequest(
        AiRequest(
          modelId: 'm',
          messages: <AiMessage>[
            AiMessage.user('同一段文字', images: <AiImagePart>[image()]),
          ],
        ),
      );
      expect(without.imageCount, 0);
      expect(withImage.imageCount, 1);
      expect(withImage.hasImages, isTrue);
      expect(
        without.promptHash,
        isNot(withImage.promptHash),
        reason: '带图的请求与纯文本请求必须是两个缓存键',
      );
    });

    test('图片摘要落进快照 JSON，但字节不进（明文备份不带图片内容）', () {
      final AiInputSnapshot snapshot = AiInputSnapshot.fromRequest(
        AiRequest(
          modelId: 'm',
          messages: <AiMessage>[
            AiMessage.user('看图', images: <AiImagePart>[image()]),
          ],
        ),
      );
      final Map<String, Object?> json = snapshot.toJson();
      final String encoded = json.toString();
      expect(json['imageCount'], 1);
      expect(encoded, contains('digest'));
      expect(
        encoded.contains('AQID') || encoded.contains('data:image'),
        isFalse,
        reason: '图片字节/编码不得进落库快照',
      );
      // 从库里读回来时图片数量仍在（字节不还原），因此「带图任务不可重放」这条规则可判。
      final AiInputSnapshot? restored = AiInputSnapshot.fromJson(json);
      expect(restored!.imageCount, 1);
      expect(restored.hasImages, isTrue);
    });
  });
}
