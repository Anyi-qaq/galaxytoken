import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import {
  CredentialField,
  CustomFieldMapping,
  CustomMode,
  CustomSourceConfig,
  FieldKind,
  MappingSemantics,
  ProviderConfig,
  ProviderDescriptor,
  ProviderSnapshot,
  FetchState
} from '../model/Types';
import { ProviderRegistry } from '../sources/ProviderRegistry';
import { CustomAdapter } from '../sources/adapters/CustomAdapter';
import { SettingsStore } from '../store/SettingsStore';
import { SecretStore } from '../store/SecretStore';
import { QuotaService } from '../service/QuotaService';
import { Log } from '../common/Logger';
import { LayoutMetrics, SizeClass, metricsFor, watchSizeClass } from '../common/Breakpoints';

interface EditParams {
  providerId: string;
}

/** 单个来源的编辑页：动态凭据表单 + 自定义映射 + 测试连接。 */
@Entry
@Component
struct ProviderEditPage {
  @State config: ProviderConfig | undefined = undefined;
  @State descriptor: ProviderDescriptor | undefined = undefined;
  @State secretValues: Record<string, string> = {};
  @State plainValues: Record<string, string> = {};
  @State baseUrl: string = '';
  @State displayName: string = '';
  @State saving: boolean = false;
  @State testing: boolean = false;
  @State message: string = '';
  @State messageOk: boolean = false;
  @State rawPreview: string = '';
  @State rawPreviewError: string = '';

  // 自定义来源专属字段
  /** 自定义来源用途：套餐 / 按量付费。 */
  @State customMode: string = CustomMode.PLAN;
  @State customUrl: string = '';
  @State customMethod: string = 'GET';
  @State customAuthMode: string = 'bearer';
  @State customAuthHeaderName: string = 'Authorization';
  @State customBodyTemplate: string = '';
  @State h5Path: string = '';
  @State h5Semantics: string = MappingSemantics.RATIO_USED;
  @State h5ResetPath: string = '';
  @State weekPath: string = '';
  @State weekSemantics: string = MappingSemantics.RATIO_USED;
  @State weekResetPath: string = '';
  @State monthPath: string = '';
  @State monthSemantics: string = MappingSemantics.RATIO_USED;
  @State monthResetPath: string = '';
  @State balancePath: string = '';
  @State balanceCurrency: string = 'CNY';
  @State limitPath: string = '';

  @State metrics: LayoutMetrics = metricsFor(SizeClass.SM);

  private providerId: string = '';
  private unwatchSize: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    const params = router.getParams() as EditParams;
    this.providerId = params === undefined || params === null ? '' : params.providerId;
    this.load();
    try {
      this.unwatchSize = watchSizeClass(this.getUIContext(), (sizeClass: SizeClass) => {
        this.metrics = metricsFor(sizeClass);
      });
    } catch (error) {
      Log.w(`size class watch failed: ${error}`);
    }
  }

  aboutToDisappear(): void {
    const unwatch = this.unwatchSize;
    if (unwatch !== undefined) {
      unwatch();
      this.unwatchSize = undefined;
    }
  }

  build() {
    Column() {
      this.header()
      if (this.config === undefined || this.descriptor === undefined) {
        Column() {
          LoadingProgress().width(30).height(30).color('#6B6B70')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          this.form()
        }
        .width('100%')
        .layoutWeight(1)
        .constraintSize({
          // 编辑表单在宽屏上限制到 760vp，避免输入框被拉得过长。
          maxWidth: 760
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#121214')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  header() {
    Row({ space: 10 }) {
      Button('返回')
        .fontSize(13)
        .height(32)
        .backgroundColor('#242428')
        .fontColor('#D8D8DC')
        .onClick(() => {
          router.back();
        })
      Text(this.descriptor === undefined ? '编辑来源' : this.descriptor.name)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F5F5F7')
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button(this.saving ? '保存中…' : '保存')
        .fontSize(13)
        .height(32)
        .backgroundColor('#3478F6')
        .fontColor('#FFFFFF')
        .enabled(!this.saving)
        .onClick(() => {
          this.save(false);
        })
    }
    .width('100%')
    .padding({
      left: this.metrics.pagePadding,
      right: this.metrics.pagePadding,
      top: 14,
      bottom: 10
    })
  }

  @Builder
  form() {
    Scroll() {
      Column({ space: 14 }) {
        if (this.descriptor !== undefined) {
          this.summaryBlock(this.descriptor)
        }
        if (ProviderRegistry.isCustom(this.providerId)) {
          this.customBlock()
        } else {
          this.credentialBlock()
        }
        this.actionBlock()
        if (this.message !== '') {
          Text(this.message)
            .fontSize(12)
            .fontColor(this.messageOk ? '#3BA55D' : '#E84026')
            .width('100%')
        }
        if (this.rawPreview !== '' || this.rawPreviewError !== '') {
          this.previewBlock()
        }
        Blank().height(30)
      }
      .width('100%')
      .padding({
        left: this.metrics.pagePadding,
        right: this.metrics.pagePadding
      })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  @Builder
  summaryBlock(descriptor: ProviderDescriptor) {
    Column({ space: 6 }) {
      Text(descriptor.summary)
        .fontSize(12)
        .fontColor('#9A9A9E')
        .width('100%')
      Row({ space: 6 }) {
        this.supportChip('5 小时', descriptor.supports.h5)
        this.supportChip('本周', descriptor.supports.week)
        this.supportChip('本月', descriptor.supports.month)
      }
      .width('100%')
      Text(descriptor.apiNote)
        .fontSize(11)
        .fontColor('#5C5C60')
        .width('100%')
      if (descriptor.experimental) {
        Text('接口未公开或未在真实账号验证，可能随时失效。')
          .fontSize(11)
          .fontColor('#F2A33C')
          .width('100%')
      }
      if (descriptor.usesBrowserSession) {
        Text('该来源依赖浏览器登录态（Cookie / OAuth），只保存在本机。')
          .fontSize(11)
          .fontColor('#7AA2F7')
          .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#1C1C1F')
    .borderRadius(12)
  }

  @Builder
  supportChip(label: string, supported: boolean) {
    Text(supported ? label : `${label} 不支持`)
      .fontSize(10)
      .fontColor(supported ? '#3BA55D' : '#6B6B70')
      .backgroundColor(supported ? '#14351F' : '#242428')
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(8)
  }

  /** 内置来源：按 descriptor 动态渲染凭据表单。 */
  @Builder
  credentialBlock() {
    Column({ space: 12 }) {
      if (this.descriptor !== undefined && this.descriptor.credentialFields.length > 0) {
        Column({ space: 12 }) {
          ForEach(this.descriptor.credentialFields, (field: CredentialField) => {
            this.fieldEditor(field)
          }, (field: CredentialField) => field.key)
        }
        .width('100%')
      } else {
        Text('该来源无需凭据。')
          .fontSize(12)
          .fontColor('#6B6B70')
          .width('100%')
      }

      if (this.descriptor !== undefined && this.descriptor.baseUrlEditable) {
        Column({ space: 6 }) {
          Text('Base URL').fontSize(12).fontColor('#9A9A9E').width('100%')
          TextInput({ text: this.baseUrl, placeholder: this.descriptor.defaultBaseUrl })
            .fontSize(13)
            .backgroundColor('#1C1C1F')
            .fontColor('#E8E8EA')
            .onChange((value: string) => {
              this.baseUrl = value;
            })
          Text('留空使用默认地址。')
            .fontSize(10)
            .fontColor('#5C5C60')
            .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#1C1C1F')
    .borderRadius(12)
  }

  @Builder
  fieldEditor(field: CredentialField) {
    Column({ space: 5 }) {
      Row({ space: 4 }) {
        Text(field.label).fontSize(12).fontColor('#9A9A9E')
        if (field.required) {
          Text('*').fontSize(12).fontColor('#E84026')
        }
      }
      .width('100%')

      if (field.kind === FieldKind.SECRET) {
        TextInput({
          text: this.secretValues[field.key] ?? '',
          placeholder: field.placeholder ?? ''
        })
          .type(InputType.Password)
          .fontSize(13)
          .backgroundColor('#242428')
          .fontColor('#E8E8EA')
          .onChange((value: string) => {
            this.secretValues[field.key] = value;
          })
      } else if (field.kind === FieldKind.CHOICE) {
        Row({ space: 8 }) {
          ForEach(field.options ?? [], (option: string) => {
            Text(option)
              .fontSize(12)
              .fontColor(this.currentChoice(field) === option ? '#FFFFFF' : '#9A9A9E')
              .backgroundColor(this.currentChoice(field) === option ? '#3478F6' : '#242428')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(8)
              .onClick(() => {
                this.plainValues[field.key] = option;
              })
          }, (option: string) => `${field.key}-${option}`)
        }
        .width('100%')
      } else {
        TextInput({
          text: this.plainValues[field.key] ?? '',
          placeholder: field.placeholder ?? ''
        })
          .fontSize(13)
          .backgroundColor('#242428')
          .fontColor('#E8E8EA')
          .onChange((value: string) => {
            this.plainValues[field.key] = value;
          })
      }

      if (field.helpText !== undefined && field.helpText !== '') {
        Text(field.helpText)
          .fontSize(10)
          .fontColor('#5C5C60')
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 自定义来源：端点、认证、字段映射。 */
  @Builder
  customBlock() {
    Column({ space: 12 }) {
      this.textField('显示名称', this.displayName, (value: string) => {
        this.displayName = value;
      }, '例如：蚂蚁 Token Plan')

      this.textField('完整 HTTPS 地址', this.customUrl, (value: string) => {
        this.customUrl = value;
      }, 'https://example.com/api/usage')

      Column({ space: 5 }) {
        Text('请求方法').fontSize(12).fontColor('#9A9A9E').width('100%')
        Row({ space: 8 }) {
          ForEach(['GET', 'POST'], (method: string) => {
            Text(method)
              .fontSize(12)
              .fontColor(this.customMethod === method ? '#FFFFFF' : '#9A9A9E')
              .backgroundColor(this.customMethod === method ? '#3478F6' : '#242428')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(8)
              .onClick(() => {
                this.customMethod = method;
              })
          }, (method: string) => `method-${method}`)
        }
        .width('100%')
      }
      .width('100%')

      Column({ space: 5 }) {
        Text('认证方式').fontSize(12).fontColor('#9A9A9E').width('100%')
        Row({ space: 8 }) {
          ForEach([
            { key: 'bearer', label: 'Bearer' },
            { key: 'header', label: '自定义头' },
            { key: 'none', label: '无需认证' }
          ], (mode: Record<string, string>) => {
            Text(mode.label)
              .fontSize(12)
              .fontColor(this.customAuthMode === mode.key ? '#FFFFFF' : '#9A9A9E')
              .backgroundColor(this.customAuthMode === mode.key ? '#3478F6' : '#242428')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(8)
              .onClick(() => {
                this.customAuthMode = mode.key;
              })
          }, (mode: Record<string, string>) => `auth-${mode.key}`)
        }
        .width('100%')
      }
      .width('100%')

      if (this.customAuthMode === 'header') {
        this.textField('认证头名称', this.customAuthHeaderName, (value: string) => {
          this.customAuthHeaderName = value;
        }, 'Authorization')
      }

      Column({ space: 5 }) {
        Text('凭据值').fontSize(12).fontColor('#9A9A9E').width('100%')
        TextInput({
          text: this.secretValues['secret'] ?? '',
          placeholder: this.customAuthMode === 'none' ? '无需填写' : 'Key / Token / Cookie'
        })
          .type(InputType.Password)
          .fontSize(13)
          .backgroundColor('#242428')
          .fontColor('#E8E8EA')
          .onChange((value: string) => {
            this.secretValues['secret'] = value;
          })
      }
      .width('100%')

      if (this.customMethod === 'POST') {
        Column({ space: 5 }) {
          Text('请求体（JSON）').fontSize(12).fontColor('#9A9A9E').width('100%')
          TextArea({ text: this.customBodyTemplate, placeholder: '{"api":"..."}' })
            .fontSize(12)
            .height(80)
            .backgroundColor('#242428')
            .fontColor('#E8E8EA')
            .onChange((value: string) => {
              this.customBodyTemplate = value;
            })
        }
        .width('100%')
      }

      Divider().color('#2C2C30')
      Text(this.isPlanCustom()
        ? '时间窗口字段（JSON 路径，例如 data.limits[0].percentage）'
        : '余额字段（JSON 路径，例如 data.balance）')
        .fontSize(12)
        .fontColor('#C8C8CC')
        .width('100%')

      if (this.isPlanCustom()) {
        this.planMappingEditors()
      } else {
        this.paygBalanceEditor()
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#1C1C1F')
    .borderRadius(12)
  }

  /** 套餐：三个时间窗口的字段映射。 */
  @Builder
  planMappingEditors() {
    this.mappingEditor('5 小时', this.h5Path, this.h5Semantics, this.h5ResetPath,
      (value: string) => {
        this.h5Path = value;
      },
      (value: string) => {
        this.h5Semantics = value;
      },
      (value: string) => {
        this.h5ResetPath = value;
      })

    this.mappingEditor('本周', this.weekPath, this.weekSemantics, this.weekResetPath,
      (value: string) => {
        this.weekPath = value;
      },
      (value: string) => {
        this.weekSemantics = value;
      },
      (value: string) => {
        this.weekResetPath = value;
      })

    this.mappingEditor('本月', this.monthPath, this.monthSemantics, this.monthResetPath,
      (value: string) => {
        this.monthPath = value;
      },
      (value: string) => {
        this.monthSemantics = value;
      },
      (value: string) => {
        this.monthResetPath = value;
      })
  }

  /** 按量付费：只需要余额金额路径与币种。 */
  @Builder
  paygBalanceEditor() {
    this.textField('余额金额路径', this.balancePath, (value: string) => {
      this.balancePath = value;
    }, 'data.balance')

    this.textField('余额币种', this.balanceCurrency, (value: string) => {
      this.balanceCurrency = value;
    }, 'CNY')
  }

  @Builder
  mappingEditor(label: string, path: string, semantics: string, resetPath: string,
    onPath: (value: string) => void, onSemantics: (value: string) => void,
    onReset: (value: string) => void) {
    Column({ space: 5 }) {
      Text(label).fontSize(12).fontColor('#9A9A9E').width('100%')
      TextInput({ text: path, placeholder: 'data.usage.percent' })
        .fontSize(12)
        .backgroundColor('#242428')
        .fontColor('#E8E8EA')
        .onChange((value: string) => {
          onPath(value);
        })
      Row({ space: 6 }) {
        ForEach([
          { key: MappingSemantics.RATIO_USED, label: '已用%' },
          { key: MappingSemantics.RATIO_REMAINING, label: '剩余%' },
          { key: MappingSemantics.ABSOLUTE, label: '绝对值' }
        ], (option: Record<string, string>) => {
          Text(option.label)
            .fontSize(11)
            .fontColor(semantics === option.key ? '#FFFFFF' : '#9A9A9E')
            .backgroundColor(semantics === option.key ? '#3478F6' : '#242428')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(7)
            .onClick(() => {
              onSemantics(option.key);
            })
        }, (option: Record<string, string>) => `${label}-${option.key}`)
      }
      .width('100%')
      TextInput({ text: resetPath, placeholder: '重置时间路径（选填）' })
        .fontSize(11)
        .backgroundColor('#242428')
        .fontColor('#E8E8EA')
        .onChange((value: string) => {
          onReset(value);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4 })
  }

  @Builder
  textField(label: string, value: string, onChange: (value: string) => void, placeholder: string) {
    Column({ space: 5 }) {
      Text(label).fontSize(12).fontColor('#9A9A9E').width('100%')
      TextInput({ text: value, placeholder: placeholder })
        .fontSize(13)
        .backgroundColor('#242428')
        .fontColor('#E8E8EA')
        .onChange((next: string) => {
          onChange(next);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  actionBlock() {
    Column({ space: 10 }) {
      Button(this.testing ? '正在测试…' : '测试连接')
        .width('100%')
        .fontSize(14)
        .height(42)
        .backgroundColor('#2A2A2E')
        .fontColor('#E8E8EA')
        .enabled(!this.testing)
        .onClick(() => {
          this.save(true);
        })
      Button('保存并启用')
        .width('100%')
        .fontSize(14)
        .height(42)
        .backgroundColor('#3478F6')
        .fontColor('#FFFFFF')
        .enabled(!this.saving)
        .onClick(() => {
          this.save(false);
        })
    }
    .width('100%')
  }

  @Builder
  previewBlock() {
    Column({ space: 6 }) {
      Text(this.rawPreviewError !== '' ? '响应预览（失败）' : '响应预览（已脱敏）')
        .fontSize(12)
        .fontColor(this.rawPreviewError !== '' ? '#E84026' : '#C8C8CC')
        .width('100%')
      Text(this.rawPreviewError !== '' ? this.rawPreviewError : this.rawPreview)
        .fontSize(10)
        .fontColor('#8A8A8E')
        .width('100%')
        .maxLines(14)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#1C1C1F')
    .borderRadius(12)
  }

  private async load(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await SettingsStore.init(context);
      const all = await SettingsStore.loadProviders();
      const found = all.find((c: ProviderConfig) => c.providerId === this.providerId);
      const descriptor = ProviderRegistry.descriptorOf(this.providerId);
      this.descriptor = descriptor;
      if (found === undefined) {
        Log.w(`config not found: ${this.providerId}`);
        return;
      }
      this.config = found;
      // 自定义来源的描述符取决于用途（套餐 / 按量付费），必须读完配置再定，
      // 否则摘要里的窗口标签会恒显示「5 小时 本周 本月」。
      if (descriptor === undefined && ProviderRegistry.isCustom(this.providerId)) {
        this.descriptor = CustomAdapter.forConfig(found).descriptor;
      }
      this.baseUrl = found.baseUrl;
      this.displayName = found.displayName ?? '';
      this.plainValues = found.plainFields ?? {};
      const secrets = await SecretStore.load(this.providerId);
      this.secretValues = secrets;
      if (found.custom !== undefined) {
        this.applyCustom(found.custom);
      }
    } catch (error) {
      Log.e(`edit load failed: ${error}`);
    }
  }

  private applyCustom(custom: CustomSourceConfig): void {
    this.customMode = custom.mode ?? CustomMode.PLAN;
    this.customUrl = custom.url ?? '';
    this.customMethod = custom.method ?? 'GET';
    this.customAuthMode = custom.authMode ?? 'bearer';
    this.customAuthHeaderName = custom.authHeaderName ?? 'Authorization';
    this.customBodyTemplate = custom.bodyTemplate ?? '';
    this.balanceCurrency = custom.balanceCurrency ?? 'CNY';
    const h5 = custom.h5;
    if (h5 !== undefined) {
      this.h5Path = h5.path;
      this.h5Semantics = h5.semantics;
      this.h5ResetPath = h5.resetPath ?? '';
      this.limitPath = h5.limitPath ?? '';
    }
    const week = custom.week;
    if (week !== undefined) {
      this.weekPath = week.path;
      this.weekSemantics = week.semantics;
      this.weekResetPath = week.resetPath ?? '';
    }
    const month = custom.month;
    if (month !== undefined) {
      this.monthPath = month.path;
      this.monthSemantics = month.semantics;
      this.monthResetPath = month.resetPath ?? '';
    }
    const balance = custom.balance;
    if (balance !== undefined) {
      this.balancePath = balance.path;
    }
  }

  /** 当前编辑的是不是「套餐」型自定义来源。 */
  private isPlanCustom(): boolean {
    return this.customMode === CustomMode.PLAN;
  }

  private buildCustomConfig(): CustomSourceConfig {
    return {
      url: this.customUrl,
      method: this.customMethod,
      authMode: this.customAuthMode,
      authHeaderName: this.customAuthHeaderName,
      extraHeaders: {},
      bodyTemplate: this.customBodyTemplate,
      mode: this.customMode as CustomMode,
      // 只保存当前用途对应的字段，切换用途后不会残留另一半配置。
      h5: this.isPlanCustom() ? this.mapping(this.h5Path, this.h5Semantics, this.h5ResetPath) : undefined,
      week: this.isPlanCustom() ? this.mapping(this.weekPath, this.weekSemantics, this.weekResetPath) : undefined,
      month: this.isPlanCustom() ? this.mapping(this.monthPath, this.monthSemantics, this.monthResetPath) : undefined,
      balance: this.isPlanCustom() || this.balancePath === '' ? undefined : {
        path: this.balancePath,
        semantics: MappingSemantics.ABSOLUTE
      },
      balanceCurrency: this.balanceCurrency
    };
  }

  private mapping(path: string, semantics: string, resetPath: string): CustomFieldMapping | undefined {
    if (path.trim() === '') {
      return undefined;
    }
    return {
      path: path.trim(),
      semantics: semantics as MappingSemantics,
      resetPath: resetPath.trim() === '' ? undefined : resetPath.trim(),
      limitPath: this.limitPath.trim() === '' ? undefined : this.limitPath.trim()
    };
  }

  private currentChoice(field: CredentialField): string {
    const value = this.plainValues[field.key];
    if (value !== undefined) {
      return value;
    }
    return field.defaultValue ?? (field.options !== undefined && field.options.length > 0 ? field.options[0] : '');
  }

  /** 保存；withTest 为 true 时先保存再测试。 */
  private async save(withTest: boolean): Promise<void> {
    if (this.config === undefined) {
      return;
    }
    if (withTest) {
      this.testing = true;
      this.message = '';
    } else {
      this.saving = true;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await SettingsStore.init(context);
      const all = await SettingsStore.loadProviders();
      const index = all.findIndex((c: ProviderConfig) => c.providerId === this.providerId);
      const isCustom = ProviderRegistry.isCustom(this.providerId);
      const plain: Record<string, string> = {};
      const plainKeys = Object.keys(this.plainValues);
      for (const key of plainKeys) {
        const value = this.plainValues[key];
        if (value !== undefined && value !== '') {
          plain[key] = value;
        }
      }
      // 选项字段若用户未动过，用默认值补齐。
      if (this.descriptor !== undefined) {
        for (const field of this.descriptor.credentialFields) {
          if (field.kind === FieldKind.CHOICE && plain[field.key] === undefined) {
            const fallback = field.defaultValue ??
              (field.options !== undefined && field.options.length > 0 ? field.options[0] : '');
            if (fallback !== '') {
              plain[field.key] = fallback;
            }
          }
        }
      }
      const secretKeys = Object.keys(this.secretValues);
      const secrets: Record<string, string> = {};
      for (const key of secretKeys) {
        const value = this.secretValues[key];
        if (value !== undefined && value.trim() !== '') {
          secrets[key] = value.trim();
        }
      }
      const updated: ProviderConfig = {
        providerId: this.providerId,
        enabled: true,
        order: index >= 0 ? all[index].order : all.length,
        baseUrl: isCustom ? this.customUrl : this.baseUrl,
        plainFields: plain,
        hasSecret: Object.keys(secrets).length > 0,
        displayName: isCustom ? this.displayName : all[index >= 0 ? index : 0].displayName,
        custom: isCustom ? this.buildCustomConfig() : undefined
      };
      if (index >= 0) {
        all[index] = updated;
      } else {
        all.push(updated);
      }
      await SettingsStore.saveProviders(all);
      if (Object.keys(secrets).length > 0) {
        await SecretStore.save(this.providerId, secrets);
      } else {
        await SecretStore.remove(this.providerId);
      }
      this.config = updated;

      const snapshot = await QuotaService.refreshOne(updated);
      this.renderTestResult(snapshot);
      if (withTest) {
        this.message = snapshot.state === FetchState.OK || snapshot.state === FetchState.PARTIAL
          ? '测试通过，已保存。' : '已保存，但测试未通过。';
        this.messageOk = snapshot.state === FetchState.OK || snapshot.state === FetchState.PARTIAL;
      } else {
        this.message = '已保存并启用。';
        this.messageOk = true;
      }
    } catch (error) {
      this.message = `保存失败：${error instanceof Error ? error.message : error}`;
      this.messageOk = false;
    } finally {
      this.saving = false;
      this.testing = false;
    }
  }

  /** 用测试结果填充响应预览。 */
  private renderTestResult(snapshot: ProviderSnapshot): void {
    this.rawPreviewError = '';
    this.rawPreview = '';
    if (snapshot.state === FetchState.OK || snapshot.state === FetchState.PARTIAL) {
      const parts: string[] = [];
      for (const window of snapshot.windows) {
        const ratio = window.usedRatio === undefined ? '—' : `${Math.round(window.usedRatio * 100)}%`;
        parts.push(`${window.kind}: 已用 ${ratio}${window.unavailableReason === undefined ? '' : `（${window.unavailableReason}）`}`);
      }
      for (const item of snapshot.balances) {
        parts.push(`余额: ${item.amount} ${item.currency}`);
      }
      if (snapshot.extra.planName !== undefined) {
        parts.push(`套餐: ${snapshot.extra.planName}`);
      }
      this.rawPreview = parts.length === 0 ? '已连通，但没有可展示的数据。' : parts.join('\n');
    } else {
      const message = snapshot.error === undefined ? '未知错误' : snapshot.error.message;
      const raw = snapshot.error === undefined ? '' : (snapshot.error.rawSnippet ?? '');
      this.rawPreviewError = raw === '' ? message : `${message}\n\n${raw}`;
    }
  }
}
