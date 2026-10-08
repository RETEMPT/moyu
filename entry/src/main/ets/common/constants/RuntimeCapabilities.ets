import { DEBUG } from 'BuildProfile';

/** Public release builds expose only the offline assistant until an auditable AI service is available. */
export const REMOTE_AI_ENABLED: boolean = DEBUG;
