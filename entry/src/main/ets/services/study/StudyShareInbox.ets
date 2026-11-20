import { Want } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { STUDY_PACKAGE_SUFFIX, STUDY_PACKAGE_UTD, StudyBackup } from '../../common/types/StudyBackup';
import { StudyBackupService } from './StudyBackupService';

/** Hold one validated package until the user imports or dismisses it. No external URI is retained. */
export class StudyShareInbox {
  private static receiving: boolean = false;
  private static pendingPackage: StudyBackup | null = null;
  private static revision: number = 0;
  private static message: string = '';

  static pending(): StudyBackup | null { return StudyShareInbox.pendingPackage; }
  static notice(): string { return StudyShareInbox.message; }

  static dismiss(id: string): void {
    if (StudyShareInbox.pendingPackage?.id !== id) { return; }
    StudyShareInbox.pendingPackage = null;
    StudyShareInbox.publish('');
  }

  static async receive(want: Want): Promise<void> {
    if (want.action !== 'ohos.want.action.sendData' || !canIUse('SystemCapability.Collaboration.SystemShare')) { return; }
    if (StudyShareInbox.receiving || StudyShareInbox.pendingPackage !== null) {
      StudyShareInbox.publish('已有资料包待处理，请完成后重新分享');
      return;
    }
    StudyShareInbox.receiving = true;
    let message = '';
    try {
      const records = (await systemShare.getSharedData(want)).getRecords();
      const record = records[0];
      const uri = record?.uri;
      if (records.length !== 1 || record.utd !== STUDY_PACKAGE_UTD || !uri || !uri.startsWith('file://') ||
        !new fileUri.FileUri(uri).name.toLowerCase().endsWith(STUDY_PACKAGE_SUFFIX)) {
        message = '请选择一份墨语 .flowmind.json 资料包';
      } else {
        StudyShareInbox.pendingPackage = await StudyBackupService.readUri(uri);
      }
    } catch {
      message = '系统分享的资料包无法读取，请保存到文件后在墨语中重新选择';
    } finally {
      StudyShareInbox.receiving = false;
      StudyShareInbox.publish(message);
    }
  }

  private static publish(message: string): void {
    StudyShareInbox.message = message;
    AppStorage.setOrCreate<number>('moyuStudyShareRevision', ++StudyShareInbox.revision);
  }
}
