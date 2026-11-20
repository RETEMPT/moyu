interface TagTone {
  lightInk: string;
  lightFill: string;
  darkInk: string;
  darkFill: string;
}

const TONES: TagTone[] = [
  { lightInk: '#265394', lightFill: '#EAF2FF', darkInk: '#AFCBFF', darkFill: '#253A59' },
  { lightInk: '#236354', lightFill: '#E5F5EF', darkInk: '#9CE0CC', darkFill: '#224239' },
  { lightInk: '#87500E', lightFill: '#FFF1D9', darkInk: '#FFD191', darkFill: '#493820' },
  { lightInk: '#943D60', lightFill: '#FCEBF2', darkInk: '#F7B3CF', darkFill: '#4D2D3B' },
  { lightInk: '#62479A', lightFill: '#F1EBFC', darkInk: '#D1B9FF', darkFill: '#3B2F52' },
  { lightInk: '#1F606C', lightFill: '#E4F4F7', darkInk: '#9BDCE8', darkFill: '#21404A' }
];

export interface NoteTagStyle {
  ink: string;
  fill: string;
  icon: string;
}

/** The same label retains its tone when records are filtered, reordered or opened in the library. */
export function noteTagStyle(label: string, dark: boolean): NoteTagStyle {
  const name = label.trim().toLowerCase();
  let hash = 0;
  for (let index = 0; index < name.length; index++) {
    hash = (Math.imul(hash, 31) + name.charCodeAt(index)) >>> 0;
  }
  let tone = TONES[hash % TONES.length];
  let icon = 'tag';
  if (/真题|考点|重点|易错|错题/.test(name)) { tone = TONES[3]; icon = 'target'; }
  else if (/考试|期中|期末|统考|截止|日程/.test(name)) { tone = TONES[2]; icon = 'calendar'; }
  else if (/复习|基础|入门|练习/.test(name)) { tone = TONES[1]; icon = 'review'; }
  else if (/计算机|系统|编程|算法/.test(name)) { tone = TONES[0]; icon = 'code'; }
  return { ink: dark ? tone.darkInk : tone.lightInk, fill: dark ? tone.darkFill : tone.lightFill, icon };
}
