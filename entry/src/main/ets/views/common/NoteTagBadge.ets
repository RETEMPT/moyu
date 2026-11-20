import { NoteTagStyle, noteTagStyle } from '../../common/theme/NoteTagStyle';
import { AppIcon } from './AppIcon';

function tagIcon(kind: string): Resource {
  switch (kind) {
    case 'target': return $r('app.media.ic_project_target');
    case 'calendar': return $r('app.media.ic_calendar');
    case 'review': return $r('app.media.ic_project_books');
    case 'code': return $r('app.media.ic_code');
    default: return $r('app.media.ic_tag');
  }
}

@Component
export struct NoteTagBadge {
  @Require @Prop tag: string;
  @Prop count: number = 0;
  @Prop selected: boolean = false;
  @Prop compact: boolean = false;
  @StorageProp('flowmindDarkMode') dark: boolean = false;

  private style(): NoteTagStyle { return noteTagStyle(this.tag, this.dark); }

  build() {
    Row({ space: 5 }) {
      AppIcon({ source: tagIcon(this.style().icon), iconSize: this.compact ? 12 : 14, tint: this.style().ink })
      Text(this.tag).fontSize(this.compact ? 11 : 12).fontWeight(FontWeight.Medium).fontColor(this.style().ink)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
      if (this.count > 0) { Text(String(this.count)).fontSize(11).fontColor(this.style().ink) }
    }.padding({ left: 8, right: 8, top: this.compact ? 3 : 5, bottom: this.compact ? 3 : 5 })
      .constraintSize({ maxWidth: this.compact ? 104 : 184 }).borderRadius(7)
      .backgroundColor(this.style().fill).border({ width: 1, color: this.selected ? this.style().ink : Color.Transparent })
  }
}
