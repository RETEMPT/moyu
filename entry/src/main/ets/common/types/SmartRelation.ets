/**
 * AI 发现的知识关联 (SmartRelation)
 */
export interface SmartRelation {
  id: string;
  sourceTitle: string;
  targetTitle: string;
  relationType: 'prerequisite' | 'related' | 'extends' | 'contrasts' | 'application';
  reason: string;
  confirmed?: boolean;
}
