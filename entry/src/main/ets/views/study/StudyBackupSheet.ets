import { common } from '@kit.AbilityKit';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { ReviewCard } from '../../common/types/StudyTypes';
import { StudyBackup } from '../../common/types/StudyBackup';
import { StudyBackupService } from '../../services/study/StudyBackupService';
import { StudyImportService } from '../../services/study/StudyImportService';
import { HarmonyNearbyService, NearbyDevice } from '../../services/sync/HarmonyNearbyService';

@Component
export struct StudyBackupSheet {
  @Prop notes: NoteItem[] = [];
  @Prop cards: ReviewCard[] = [];
  @Prop @Watch('closeRequested') closeToken: number = 0;
  onClose: () => void = () => {};
  onRestore: (note: NoteItem, cards: ReviewCard[]) => Promise<void> = async () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @State course: string = '';
  @State backup: StudyBackup | null = null;
  @State busy: boolean = false;
  @State status: string = '';
  @State nearby: boolean = false;
  @State devices: NearbyDevice[] = [];
  @State deviceId: string = '';
  @State receiveCode: string = '';
  @State sentCode: string = '';
  private transfer: HarmonyNearbyService = new HarmonyNearbyService();
  private alive: boolean = true;
  aboutToAppear(): void { this.alive = true; }
  aboutToDisappear(): void { this.alive = false; this.transfer.close(); }
  private closeRequested(): void { if (!this.busy) { this.onClose(); } }
  private palette() { return ThemeHelper.paletteOfDark(this.dark); }
  private async exportFile(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      const notes = this.notes.filter((note: NoteItem) => !this.course || (note.category || '未分类') === this.course);
      if (!notes.length) { throw new Error('此课程没有资料，请核对分类名'); }
      const ok = await StudyBackupService.exportFile(getContext(this) as common.UIAbilityContext, notes, this.cards);
      if (this.alive) { this.status = ok ? '学习资料备份已导出。建议先在另一设备验证恢复。' : '已取消导出'; }
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '导出失败'; } }
    finally { if (this.alive) { this.busy = false; } }
  }
  private async selectFile(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    this.backup = null;
    try {
      const backup = await StudyBackupService.selectFile(getContext(this) as common.UIAbilityContext);
      if (this.alive) { this.backup = backup; this.status = backup ? '请核对数量，确认后按副本导入。' : '已取消选择'; }
    }
    catch (error) { this.status = (error as Error).message || '备份无法读取'; }
    finally { if (this.alive) { this.busy = false; } }
  }
  private async restore(): Promise<void> {
    const backup = this.backup;
    if (!backup || this.busy) { return; } this.busy = true;
    try {
      const result = await StudyImportService.restore(getContext(this) as common.UIAbilityContext, backup, {
        notes: () => this.notes, commit: this.onRestore, progress: (message: string) => { if (this.alive) { this.status = message; } }
      });
      if (this.alive) { this.status = `已导入 ${result.imported} 份资料，跳过 ${result.skipped} 份已恢复资料。原资料保留。`; }
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '导入中断，可重试'; } }
    finally { if (this.alive) { this.busy = false; } }
  }

  private async connectDevices(): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.nearby = true; this.sentCode = '';
    try {
      await this.transfer.close(); if (!this.alive) { return; } this.transfer = new HarmonyNearbyService();
      const devices = await this.transfer.connect(getContext(this) as common.UIAbilityContext);
      if (this.alive) {
        this.devices = devices; this.deviceId = devices.length ? devices[0].id : '';
        this.status = devices.length ? '请选择目标设备；两端均需打开本页并连接。' : '未发现可用可信设备，请核对系统设备连接后刷新。';
      }
    } catch (error) { if (this.alive) { this.devices = []; this.deviceId = ''; this.status = (error as Error).message || '连接失败'; } }
    finally { if (this.alive) { this.busy = false; } }
  }

  private async sendNearby(): Promise<void> {
    if (this.busy || !this.deviceId) { return; } this.busy = true; this.sentCode = '';
    try {
      const notes = this.notes.filter((note: NoteItem) => !this.course || (note.category || '未分类') === this.course);
      const backup = await StudyBackupService.create(getContext(this) as common.UIAbilityContext, notes, this.cards);
      if (!this.alive) { return; }
      this.status = '正在传递完整资料，请保持两端连接…';
      const code = await this.transfer.send(this.deviceId, backup);
      if (this.alive) { this.sentCode = code; this.status = '资料已传递，请在对端填写传递码并确认导入。保持本页打开；15 分钟内有效。'; }
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '传递未完成'; } }
    finally { if (this.alive) { this.busy = false; } }
  }

  private async receiveNearby(): Promise<void> {
    if (this.busy || !this.deviceId) { return; } this.busy = true; this.backup = null;
    try {
      this.status = '正在接收并核验资料…';
      const backup = await this.transfer.receive(this.deviceId, this.receiveCode);
      if (this.alive) { this.backup = backup; this.status = '完整性校验通过，请核对资料并确认导入为副本。'; }
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '接收未完成'; } }
    finally { if (this.alive) { this.busy = false; } }
  }
  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('备份与附近传递').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
          Button('关闭').height(44).enabled(!this.busy).onClick(() => this.onClose())
        }.width('100%')
        Scroll() {
        Column({ space: 12 }) {
        Text('包含笔记、原 PDF、自定义封面、笔迹、已提取页面和复习题卡。日历、回收站、会话与模型密钥不在此备份内。')
          .fontSize(14).fontColor(this.palette().inkSecondary).width('100%')
        Text('文件未加密，请保存到可信位置；可自行存到系统文件选择器支持的网盘。恢复会创建副本，每份资料独立保存。')
          .fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
        Text('随包示例只备份现有正文与笔迹，恢复后仍标为示例，不包含原 PDF。').fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
        Text('单个附件最多 16 MB，备份文件最多 32 MB。资料较多时可按课程分批导出。').fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
        TextInput({ text: this.course, placeholder: '只备份某课程：填写分类名；留空备份全部' }).enabled(!this.busy).onChange((value: string) => { this.course = value.trim(); })
        Button('导出学习资料').height(44).width('100%').enabled(!this.busy).onClick(() => this.exportFile())
        Button('选择备份文件').height(44).width('100%').enabled(!this.busy).onClick(() => this.selectFile())
        Button('附近传递（试用）· 连接设备').height(44).width('100%').enabled(!this.busy).onClick(() => this.connectDevices())
        if (this.nearby) {
          Text('附近传递（试用）').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
          Text('两端需安装同一来源、相同版本的墨语，并在系统中建立可信连接。建议同一华为帐号、同一网络；两端保持本页打开。')
            .fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
          Text('手动传递学习资料并导入副本；暂不自动合并修改、同步删除或传递日历、会话、密钥。大批资料请使用文件备份。')
            .fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
          ForEach(this.devices, (device: NearbyDevice) => {
            Button(`${this.deviceId === device.id ? '已选择 · ' : ''}${device.name}`).height(44).width('100%').enabled(!this.busy)
              .onClick(() => { this.deviceId = device.id; })
          }, (device: NearbyDevice) => device.id)
          Button('发送所选课程资料').height(44).width('100%').enabled(!this.busy && !!this.deviceId).onClick(() => this.sendNearby())
          if (this.sentCode) {
            Text(`传递码：${this.sentCode}`).fontSize(16).fontColor(this.palette().inkPrimary).copyOption(CopyOptions.InApp).width('100%')
          }
          TextInput({ text: this.receiveCode, placeholder: '接收：填写另一设备显示的传递码' }).enabled(!this.busy)
            .onChange((value: string) => { this.receiveCode = value.trim(); })
          Button('接收并核对资料').height(44).width('100%').enabled(!this.busy && !!this.deviceId && !!this.receiveCode).onClick(() => this.receiveNearby())
          if (this.busy) {
            Button('取消附近连接').height(44).width('100%').onClick(() => { this.transfer.close(); })
          }
        }
        if (this.backup) {
          Text(`${this.backup.notes.length} 份资料 · ${this.backup.cards.length} 道题卡 · ${this.backup.assets.length} 个附件`)
            .fontSize(14).fontColor(this.palette().inkPrimary).width('100%')
          Button('确认导入为副本').height(44).width('100%').enabled(!this.busy).onClick(() => this.restore())
        }
        if (this.status) { Text(this.status).fontSize(13).fontColor(this.palette().accent).width('100%') }
        }.width('100%')
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      }.padding(20).width(this.phone ? '94%' : 580).height('86%').borderRadius(18).backgroundColor(this.palette().surface)
        .onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.4)').onClick(() => { if (!this.busy) { this.onClose(); } })
  }
}
