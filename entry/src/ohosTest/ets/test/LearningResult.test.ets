import { describe, it, expect } from '@ohos/hypium';
import { LearningResultPolicy } from '../../../main/ets/services/study/LearningResultPolicy';

export default function learningResultTest() {
  describe('OfflineLearningResult', () => {
    it('rejects unsupported result without adopting data', 0, () => {
      let rejected = false;
      try { LearningResultPolicy.parse('{"format":"unsupported"}'); }
      catch { rejected = true; }
      expect(rejected).assertTrue();
    });
    it('rejects bytes beyond the interchange limit', 0, () => {
      let rejected = false;
      try { LearningResultPolicy.parse(' '.repeat(131073)); }
      catch { rejected = true; }
      expect(rejected).assertTrue();
    });
  });
}
