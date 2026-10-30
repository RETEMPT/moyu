/** Offline interchange only. No application identity, credentials or save authority. */
export interface LearningCitation {
  source_id: string;
  quote: string;
}
export interface LearningSource {
  id: string;
  name: string;
  text: string;
  revision: number;
  digest: string;
  line_start: number;
  line_end: number;
}
export interface LearningSection {
  heading: string;
  body: string;
  citations: LearningCitation[];
}
export interface LearningCardCandidate {
  question: string;
  answer: string;
  citations: LearningCitation[];
}
export interface LearningResult {
  format: string;
  version: number;
  job_id: string;
  operation: string;
  title: string;
  sources: LearningSource[];
  sections: LearningSection[];
  cards: LearningCardCandidate[];
  warnings: string[];
}
