/* eslint-disable */
import OpenAI from "openai";
import {setGlobalOptions} from "firebase-functions/v2";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

setGlobalOptions({maxInstances: 10});

const openAiKeySecret = defineSecret("OPENAI_API_KEY");
const DEFAULT_MODEL = process.env.OPENAI_MODEL || "gpt-4o-mini";
const DEFAULT_TIMEZONE = "Australia/Adelaide";
const MAX_SUMMARY_CHARS = 150;

interface DraftEvent {
  title: string;
  startISO?: string;
  endISO?: string;
  dateISO?: string;
  timeISO?: string;
  timezone?: string;
  participants?: string[];
  location?: string;
  notes?: string;
  confidence?: number;
}

interface ChatWithAIRequest {
  message?: unknown;
  conversationId?: unknown;
  timezone?: unknown;
}

interface ChatWithAIResponse {
  reply: string;
  draftEvents?: DraftEvent[];
}

interface SummarizeVoiceMemoRequest {
  input?: unknown;
  inputMode?: unknown;
  timezone?: unknown;
  currentDateISO?: unknown;
}

interface VoiceMemoSummaryResponse {
  title: string;
  summary: string;
  detailedSummary: string;
  keyPoints: string[];
  actionItems: string[];
  category: string;
}

interface AnalyzeMemoTaskRequest {
  title?: unknown;
  body?: unknown;
  timezone?: unknown;
  currentDateISO?: unknown;
}

interface MemoTaskDraftResponse {
  title: string;
  notes: string;
  category?: string;
  dateISO?: string;
  time24h?: string;
  reminderEnabled: boolean;
  confidence?: number;
}

const rateLimitWindowMs = 10 * 1000;
const rateLimitMaxCalls = 3;
const userCallTimestamps = new Map<string, number[]>();

//const pruneAndCheckRateLimit = (uid: string): void => {
const pruneAndCheckRateLimit = (key: string): void => {
  const now = Date.now();
  //const timestamps = userCallTimestamps.get(uid) || [];
  const timestamps = userCallTimestamps.get(key) || [];
  const fresh = timestamps.filter((ts) => now - ts < rateLimitWindowMs);

  if (fresh.length >= rateLimitMaxCalls) {
    throw new HttpsError(
      "resource-exhausted",
      "Too many requests. Please wait a few seconds and try again."
    );
  }

  fresh.push(now);
//   userCallTimestamps.set(uid, fresh);
  userCallTimestamps.set(key, fresh);
};

const parseAssistantJson = (content: string): ChatWithAIResponse => {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch (error) {
    logger.error("Assistant response is not valid JSON", error);
    throw new HttpsError("internal", "AI response format error.");
  }

  if (!parsed || typeof parsed !== "object") {
    throw new HttpsError("internal", "AI response format invalid.");
  }

  const candidate = parsed as Record<string, unknown>;
  const reply = typeof candidate.reply === "string" ? candidate.reply.trim() : "";
  if (!reply) {
    throw new HttpsError("internal", "AI response missing reply.");
  }

  const response: ChatWithAIResponse = {reply};

  if (Array.isArray(candidate.draftEvents)) {
    const draftEvents: DraftEvent[] = candidate.draftEvents
      .filter((item) => item && typeof item === "object")
      .map((item) => {
        const event = item as Record<string, unknown>;
        return {
          title: typeof event.title === "string" ? event.title : "Untitled",
          startISO: typeof event.startISO === "string" ? event.startISO : undefined,
          endISO: typeof event.endISO === "string" ? event.endISO : undefined,
          dateISO: typeof event.dateISO === "string" ? event.dateISO : undefined,
          timeISO: typeof event.timeISO === "string" ? event.timeISO : undefined,
          timezone: typeof event.timezone === "string" ? event.timezone : undefined,
          participants: Array.isArray(event.participants) ?
            event.participants.filter((p): p is string => typeof p === "string") : undefined,
          location: typeof event.location === "string" ? event.location : undefined,
          notes: typeof event.notes === "string" ? event.notes : undefined,
          confidence: typeof event.confidence === "number" ? event.confidence : undefined,
        };
      });

    if (draftEvents.length > 0) {
      response.draftEvents = draftEvents;
    }
  }

  return response;
};

const parseVoiceMemoJson = (content: string): VoiceMemoSummaryResponse => {
  let parsed: unknown;
  try {
    const trimmed = content.trim();
    const jsonContent =
      trimmed.startsWith("```") ?
        trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "") :
        trimmed;
    parsed = JSON.parse(jsonContent);
  } catch (error) {
    logger.error("Voice memo response is not valid JSON", error);
    throw new HttpsError("internal", "AI response format error.");
  }

  if (!parsed || typeof parsed !== "object") {
    throw new HttpsError("internal", "AI response format invalid.");
  }

  const candidate = parsed as Record<string, unknown>;
  const title = typeof candidate.title === "string" ? candidate.title.trim() : "";
  const summary = typeof candidate.summary === "string" ? candidate.summary.trim() : "";
  const detailedSummary =
    typeof candidate.detailedSummary === "string" ?
      candidate.detailedSummary.trim() :
      "";
  const category = typeof candidate.category === "string" ? candidate.category.trim() : "Memo";

  if (!title || !summary || !detailedSummary) {
    throw new HttpsError("internal", "AI memo response missing required fields.");
  }

  const keyPoints = Array.isArray(candidate.keyPoints) ?
    candidate.keyPoints
      .filter((item): item is string => typeof item === "string")
      .map((item) => item.trim())
      .filter((item) => item.length > 0) :
    [];

  const actionItems = Array.isArray(candidate.actionItems) ?
    candidate.actionItems
      .filter((item): item is string => typeof item === "string")
      .map((item) => item.trim())
      .filter((item) => item.length > 0) :
    [];

  return {
    title,
    summary: limitText(summary),
    detailedSummary: limitText(detailedSummary),
    keyPoints: limitTextItems(keyPoints),
    actionItems: limitTextItems(actionItems),
    category: category || "Memo",
  };
};

const isValidDateISO = (value: string): boolean => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
};

const formatDateInTimezone = (date: Date, timezone: string): string => {
  const build = (timeZone: string): string => {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(date);

    const year = parts.find((part) => part.type === "year")?.value;
    const month = parts.find((part) => part.type === "month")?.value;
    const day = parts.find((part) => part.type === "day")?.value;

    if (!year || !month || !day) {
      throw new Error("Unable to format current date.");
    }

    return `${year}-${month}-${day}`;
  };

  try {
    return build(timezone);
  } catch (_) {
    return build(DEFAULT_TIMEZONE);
  }
};

const resolveCurrentDateISO = (value: unknown, timezone: string): string => {
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (isValidDateISO(trimmed)) {
      return trimmed;
    }
  }

  return formatDateInTimezone(new Date(), timezone);
};

const addDaysToDateISO = (dateISO: string, days: number): string => {
  const date = new Date(`${dateISO}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
};

const inferRelativeDateISO = (input: string, currentDateISO: string): string | undefined => {
  const normalized = input.toLowerCase();

  if (/(后天|day after tomorrow)/i.test(normalized)) {
    return addDaysToDateISO(currentDateISO, 2);
  }

  if (/(明天|tomorrow)/i.test(normalized)) {
    return addDaysToDateISO(currentDateISO, 1);
  }

  if (/(今天|今日|today)/i.test(normalized)) {
    return currentDateISO;
  }

  return undefined;
};

const normalizeMemoTaskDateISO = (
  value: string | undefined,
  sourceText: string,
  currentDateISO: string
): string | undefined => {
  const inferredDateISO = inferRelativeDateISO(sourceText, currentDateISO);
  if (inferredDateISO) {
    return inferredDateISO;
  }

  const trimmed = value?.trim();
  if (!trimmed || !isValidDateISO(trimmed)) {
    return undefined;
  }

  const currentYear = Number(currentDateISO.slice(0, 4));
  const draftYear = Number(trimmed.slice(0, 4));
  const hasExplicitYear = /\b(?:19|20)\d{2}\b/.test(sourceText);
  if (!hasExplicitYear && draftYear < currentYear) {
    return undefined;
  }

  return trimmed;
};

const limitText = (value: string, maxChars = MAX_SUMMARY_CHARS): string => {
  const normalized = value.replace(/\s+/g, " ").trim();
  const chars = Array.from(normalized);
  if (chars.length <= maxChars) {
    return normalized;
  }

  return chars.slice(0, maxChars).join("").trimEnd();
};

const limitTextItems = (items: string[]): string[] =>
  items
    .map((item) => limitText(item))
    .filter((item) => item.length > 0);

const parseMemoTaskJson = (content: string): MemoTaskDraftResponse => {
  let parsed: unknown;
  try {
    const trimmed = content.trim();
    const jsonContent =
      trimmed.startsWith("```") ?
        trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "") :
        trimmed;
    parsed = JSON.parse(jsonContent);
  } catch (error) {
    logger.error("Memo task response is not valid JSON", error);
    throw new HttpsError("internal", "AI response format error.");
  }

  if (!parsed || typeof parsed !== "object") {
    throw new HttpsError("internal", "AI response format invalid.");
  }

  const candidate = parsed as Record<string, unknown>;
  const title = typeof candidate.title === "string" ? candidate.title.trim() : "";
  const notes = typeof candidate.notes === "string" ? candidate.notes.trim() : "";

  if (!title && !notes) {
    throw new HttpsError("internal", "AI task response missing usable fields.");
  }

  return {
    title,
    notes,
    category: typeof candidate.category === "string" ? candidate.category.trim() : undefined,
    dateISO: typeof candidate.dateISO === "string" ? candidate.dateISO.trim() : undefined,
    time24h: typeof candidate.time24h === "string" ? candidate.time24h.trim() : undefined,
    reminderEnabled: typeof candidate.reminderEnabled === "boolean" ? candidate.reminderEnabled : true,
    confidence: typeof candidate.confidence === "number" ? candidate.confidence : undefined,
  };
};

const detectVoiceMemoCategory = (input: string): string => {
  const normalized = input.toLowerCase();

  if (/(meeting|project|deadline|client|demo|team|work)/.test(normalized)) {
    return "Work";
  }

  if (/(family|mom|dad|child|kids|home|share)/.test(normalized)) {
    return "Family";
  }

  if (/(doctor|health|exercise|medicine|sleep)/.test(normalized)) {
    return "Health";
  }

  if (/(study|school|class|assignment|exam|course)/.test(normalized)) {
    return "Study";
  }

  if (/(buy|shopping|groceries|pick up|errand|store)/.test(normalized)) {
    return "Errand";
  }

  return "Memo";
};

const buildVoiceMemoFallback = (input: string): VoiceMemoSummaryResponse => {
  const cleaned = input.replace(/\s+/g, " ").trim();
  const segments = cleaned
    .split(/(?<=[.!?])\s+/)
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0);

  const titleSource = segments[0] || cleaned;
  const titleWords = titleSource.split(" ").filter((word) => word.length > 0).slice(0, 8);
  const title = titleWords.join(" ") || "Voice memo";
  const summary =
    segments.slice(0, 2).join(" ").trim() ||
    cleaned.substring(0, 160).trim();
  const detailedSummary =
    segments.slice(0, 4).join(" ").trim() ||
    cleaned;

  const keyPoints = segments.slice(0, 3);
  const actionItems = segments
    .filter((segment) => /(need to|should|plan to|must|follow up|next)/i.test(segment))
    .slice(0, 3);

  return {
    title,
    summary: limitText(summary || "Summary generated from the memo content."),
    detailedSummary:
      limitText(detailedSummary || "Detailed summary generated from the memo content."),
    keyPoints: limitTextItems(keyPoints),
    actionItems: limitTextItems(actionItems),
    category: detectVoiceMemoCategory(cleaned),
  };
};

export const chatWithAI = onCall(
  {secrets: [openAiKeySecret], region: "australia-southeast1" },
  async (request): Promise<ChatWithAIResponse> => {
//     if (!request.auth?.uid) {
//       throw new HttpsError("unauthenticated", "You must be logged in to use AI chat.");
//     }
//
//     pruneAndCheckRateLimit(request.auth.uid);
    const callerKey =
          request.auth?.uid ||
          (request.rawRequest as any)?.ip ||
          "anon";

    pruneAndCheckRateLimit(callerKey);

    const data = (request.data ?? {}) as ChatWithAIRequest;
    const message = typeof data.message === "string" ? data.message.trim() : "";
    const conversationId =
      typeof data.conversationId === "string" ? data.conversationId.trim() : "";
    const timezone =
      typeof data.timezone === "string" && data.timezone.trim().length > 0 ?
        data.timezone.trim() :
        DEFAULT_TIMEZONE;

    if (!message) {
      throw new HttpsError("invalid-argument", "message is required.");
    }

    const apiKey = openAiKeySecret.value() || process.env.OPENAI_API_KEY;
    if (!apiKey) {
      logger.error("OPENAI_API_KEY is missing");
      throw new HttpsError("internal", "Server is not configured for AI service.");
    }

    const openai = new OpenAI({apiKey});

    const systemPrompt = [
      "You are the Family Calendar AI Assistant.",
      "Help users organize schedules, reminders, and todos from conversation.",
      "Return strict JSON with two top-level fields: reply (string) and draftEvents (array).",
      "In reply: be friendly, concise, and confirm key details.",
      "In draftEvents: include possible schedule/reminder drafts when detected.",
      "Prefer startISO/endISO, or dateISO/timeISO when full datetime is unavailable.",
      "Never fabricate dates or times. If any critical detail is missing, ask a clarifying question.",
      "Do not output sensitive data.",
      "Do not claim that events are already created.",
      `Default timezone is ${timezone}.`,
      "If no event-like intent exists, return an empty draftEvents array.",
    ].join(" ");

    const developerPrompt = [
      "Return JSON only.",
      "Schema:",
      "{",
      "  \"reply\": \"string\",",
      "  \"draftEvents\": [",
      "    {",
      "      \"title\": \"string\",",
      "      \"startISO\": \"string (optional)\",",
      "      \"endISO\": \"string (optional)\",",
      "      \"dateISO\": \"string (optional)\",",
      "      \"timeISO\": \"string (optional)\",",
      "      \"timezone\": \"string (optional)\",",
      "      \"participants\": [\"string\"] (optional),",
      "      \"location\": \"string (optional)\",",
      "      \"notes\": \"string (optional)\",",
      "      \"confidence\": \"number 0..1 (optional)\"",
      "    }",
      "  ]",
      "}",
      "Use English in reply.",
      "Use conversationId only as metadata context if provided; do not expose secrets.",
    ].join("\n");

    const userPrompt = `conversationId: ${conversationId || "n/a"}\nuserMessage: ${message}`;

    try {
      const completion = await openai.chat.completions.create({
        model: DEFAULT_MODEL,
        temperature: 0.2,
        response_format: {type: "json_object"},
        messages: [
          {role: "system", content: systemPrompt},
          {role: "developer", content: developerPrompt},
          {role: "user", content: userPrompt},
        ],
      });

      const content = completion.choices[0]?.message?.content;
      if (!content) {
        throw new HttpsError("internal", "No response from AI model.");
      }

      return parseAssistantJson(content);
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("chatWithAI failed", error);
      throw new HttpsError("internal", "Failed to process AI request.");
    }
  }
);

export const summarizeVoiceMemo = onCall(
  {secrets: [openAiKeySecret], region: "australia-southeast1"},
  async (request): Promise<VoiceMemoSummaryResponse> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "You must be logged in to summarize a memo.");
    }

    pruneAndCheckRateLimit(request.auth.uid);

    const data = (request.data ?? {}) as SummarizeVoiceMemoRequest;
    const input = typeof data.input === "string" ? data.input.trim() : "";
    const inputMode = typeof data.inputMode === "string" ? data.inputMode.trim() : "text";
    const timezone =
      typeof data.timezone === "string" && data.timezone.trim().length > 0 ?
        data.timezone.trim() :
        DEFAULT_TIMEZONE;
    const currentDateISO = resolveCurrentDateISO(data.currentDateISO, timezone);

    if (!input) {
      throw new HttpsError("invalid-argument", "input is required.");
    }

    const apiKey = openAiKeySecret.value() || process.env.OPENAI_API_KEY;
    if (!apiKey) {
      logger.error("OPENAI_API_KEY is missing");
      throw new HttpsError("internal", "Server is not configured for AI service.");
    }

    const openai = new OpenAI({apiKey});

    const systemPrompt = [
      "You are the Family Calendar voice memo assistant.",
      "Turn raw personal notes into a clean structured summary.",
      "Preserve user intent, avoid fabrication, and be concise but helpful.",
      "Infer a short memo category such as Family, Work, Health, Study, Errand, or Personal.",
      "If action items are implied, list them briefly. If none exist, return an empty array.",
      `Assume timezone ${timezone} for interpretation context only.`,
      `The current local date is ${currentDateISO}.`,
    ].join(" ");

    const developerPrompt = [
      "Return JSON only.",
      "Schema:",
      "{",
      "  \"title\": \"string up to 8 words\",",
      `  "summary": "string, 1-2 sentences, max ${MAX_SUMMARY_CHARS} characters",`,
      `  "detailedSummary": "string, concise paragraph, max ${MAX_SUMMARY_CHARS} characters",`,
      "  \"keyPoints\": [\"string\"],",
      "  \"actionItems\": [\"string\"],",
      "  \"category\": \"string\"",
      "}",
      "Keep the output in English.",
      "Do not mention the schema.",
      `Keep summary, detailedSummary, and each list item within ${MAX_SUMMARY_CHARS} characters.`,
      "Do not invent dates, people, or commitments not present in the input.",
    ].join("\n");

    const userPrompt = `inputMode: ${inputMode}\nrawInput: ${input}`;

    try {
      const completion = await openai.chat.completions.create({
        model: DEFAULT_MODEL,
        temperature: 0.2,
        response_format: {type: "json_object"},
        messages: [
          {role: "system", content: systemPrompt},
          {role: "developer", content: developerPrompt},
          {role: "user", content: userPrompt},
        ],
      });

      const content = completion.choices[0]?.message?.content;
      if (!content) {
        throw new HttpsError("internal", "No response from AI model.");
      }

      return parseVoiceMemoJson(content);
    } catch (error) {
      if (error instanceof HttpsError && error.code === "invalid-argument") {
        throw error;
      }

      logger.error("summarizeVoiceMemo failed", error);
      return buildVoiceMemoFallback(input);
    }
  }
);

export const analyzeMemoToTask = onCall(
  {secrets: [openAiKeySecret], region: "australia-southeast1"},
  async (request): Promise<MemoTaskDraftResponse> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "You must be logged in to analyze a memo.");
    }

    pruneAndCheckRateLimit(request.auth.uid);

    const data = (request.data ?? {}) as AnalyzeMemoTaskRequest;
    const title = typeof data.title === "string" ? data.title.trim() : "";
    const body = typeof data.body === "string" ? data.body.trim() : "";
    const timezone =
      typeof data.timezone === "string" && data.timezone.trim().length > 0 ?
        data.timezone.trim() :
        DEFAULT_TIMEZONE;
    const currentDateISO = resolveCurrentDateISO(data.currentDateISO, timezone);

    if (!title && !body) {
      throw new HttpsError("invalid-argument", "Memo content is required.");
    }

    const apiKey = openAiKeySecret.value() || process.env.OPENAI_API_KEY;
    if (!apiKey) {
      logger.error("OPENAI_API_KEY is missing");
      throw new HttpsError("internal", "Server is not configured for AI service.");
    }

    const openai = new OpenAI({apiKey});

    const systemPrompt = [
      "You are the Family Calendar memo-to-task assistant.",
      "Read one memo and extract only clear event details that can prefill an add-task form.",
      "Never fabricate dates, times, titles, or reminders.",
      "If a field is unclear, leave it empty instead of guessing.",
      "Allowed category values are Education, Family, Leisure.",
      `Interpret date and time references in timezone ${timezone}.`,
      `The current local date is ${currentDateISO}.`,
    ].join(" ");

    const developerPrompt = [
      "Return JSON only.",
      "Schema:",
      "{",
      "  \"title\": \"string\",",
      "  \"notes\": \"string\",",
      "  \"category\": \"Education | Family | Leisure | empty string\",",
      "  \"dateISO\": \"YYYY-MM-DD or empty string\",",
      "  \"time24h\": \"HH:mm or empty string\",",
      "  \"reminderEnabled\": true,",
      "  \"confidence\": \"number 0..1\"",
      "}",
      "Use memo wording where possible.",
      "If memo title is usable as task title, prefer it.",
      "Put the memo body into notes when it helps the user review context.",
      `When the memo says today/今天/今日, use ${currentDateISO}.`,
      `When the memo says tomorrow/明天, use ${addDaysToDateISO(currentDateISO, 1)}.`,
      `When the memo says 后天/day after tomorrow, use ${addDaysToDateISO(currentDateISO, 2)}.`,
      "Do not invent a date or time from weak hints.",
    ].join("\n");

    const userPrompt = `memoTitle: ${title || "n/a"}\nmemoBody: ${body || "n/a"}`;

    try {
      const completion = await openai.chat.completions.create({
        model: DEFAULT_MODEL,
        temperature: 0.1,
        response_format: {type: "json_object"},
        messages: [
          {role: "system", content: systemPrompt},
          {role: "developer", content: developerPrompt},
          {role: "user", content: userPrompt},
        ],
      });

      const content = completion.choices[0]?.message?.content;
      if (!content) {
        throw new HttpsError("internal", "No response from AI model.");
      }

      const draft = parseMemoTaskJson(content);
      const sourceText = `${title}\n${body}`;
      return {
        ...draft,
        dateISO: normalizeMemoTaskDateISO(draft.dateISO, sourceText, currentDateISO),
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("analyzeMemoToTask failed", error);
      throw new HttpsError("internal", "Failed to analyze memo.");
    }
  }
);
