/**
 * 桌面服务卡片。
 *
 * 两种尺寸共用一份数据：
 * - 2*2：最紧张的窗口环形进度 + 来源名 + 重置倒计时；
 * - 4*4：在 2*2 基础上多列最多 3 个来源的三窗口摘要与余额合计。
 *
 * 卡片只做渲染，不发网络请求；数据由 QuotaFormAbility 通过 updateForm 推送。
 * 点击整卡打开主应用。
 */
const storage: LocalStorage = new LocalStorage();

@Entry(storage)
@Component
struct QuotaCard {
  @LocalStorageProp('headlineTitle') headlineTitle: string = '星河 Token';
  @LocalStorageProp('headlineLabel') headlineLabel: string = '';
  @LocalStorageProp('headlineValue') headlineValue: string = '—';
  @LocalStorageProp('headlinePercent') headlinePercent: number = 0;
  @LocalStorageProp('headlineReset') headlineReset: string = '';
  @LocalStorageProp('headlineColor') headlineColor: string = '#9A9A9E';
  @LocalStorageProp('rowCount') rowCount: number = 0;
  @LocalStorageProp('row1') row1: string = '';
  @LocalStorageProp('row2') row2: string = '';
  @LocalStorageProp('row3') row3: string = '';
  @LocalStorageProp('balanceText') balanceText: string = '';
  @LocalStorageProp('updatedText') updatedText: string = '打开应用以获取数据';

  build() {
    Column() {
      // 2*2 与 4*4 用同一套内容，靠 GridRow 的列宽自动适配密度。
      Row({ space: 12 }) {
        this.ring()
        Column({ space: 2 }) {
          Text(this.headlineTitle)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#F5F5F7')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.headlineLabel)
            .fontSize(10)
            .fontColor('#8A8A8E')
            .maxLines(1)
          Text(this.headlineReset)
            .fontSize(10)
            .fontColor('#9A9A9E')
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      if (this.rowCount > 0) {
        Column({ space: 3 }) {
          Divider().color('#2C2C30')
          if (this.row1 !== '') {
            this.row(this.row1)
          }
          if (this.row2 !== '') {
            this.row(this.row2)
          }
          if (this.row3 !== '') {
            this.row(this.row3)
          }
        }
        .width('100%')
        .margin({ top: 8 })
      }

      Blank()

      Row() {
        Text(this.balanceText)
          .fontSize(10)
          .fontColor('#8A8A8E')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.updatedText)
          .fontSize(10)
          .fontColor('#8A8A8E')
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#161618')
    .borderRadius(16)
    .onClick(() => {
      // 点击整卡拉起主应用首页。
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { target: 'index' }
      });
    })
  }

  @Builder
  ring() {
    Stack() {
      Progress({
        value: this.headlinePercent,
        total: 100,
        type: ProgressType.Ring
      })
        .color(this.headlineColor)
        .backgroundColor('#2A2A2E')
        .width(56)
        .height(56)
        .style({ strokeWidth: 7 })
      Text(this.headlineValue)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F5F5F7')
    }
    .width(56)
    .height(56)
  }

  @Builder
  row(content: string) {
    Text(content)
      .fontSize(10)
      .fontColor('#C8C8CC')
      .width('100%')
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
}
