type AppEnv = {
	vestigo: D1Database;
	TMDB_API_KEY?: string;
};

type TrackedItemInput = {
	tmdbID?: number;
	tmdbId?: number;
	kind?: string;
	title?: string;
	releaseDate?: string | null;
	reason?: string;
};

type SyncTrackedItemsRequest = {
	userID?: string;
	userId?: string;
	items?: TrackedItemInput[];
};

type TrackedItemRow = {
	id: string;
	user_id: string;
	tmdb_id: number;
	kind: string;
	title: string;
	release_date: string | null;
	reason: string;
};

const jsonHeaders = {
	"content-type": "application/json; charset=utf-8",
	"access-control-allow-origin": "*",
	"access-control-allow-methods": "GET,POST,OPTIONS",
	"access-control-allow-headers": "content-type,authorization",
};

export default {
	async fetch(request: Request, env: AppEnv): Promise<Response> {
		if (request.method === "OPTIONS") {
			return new Response(null, { status: 204, headers: jsonHeaders });
		}

		const url = new URL(request.url);

		try {
			if (url.pathname === "/" || url.pathname === "/health") {
				return json({ ok: true, app: "Vestigo backend" });
			}

			if (url.pathname === "/sync-tracked-items" && request.method === "POST") {
				return syncTrackedItems(request, env);
			}

			if (url.pathname === "/notifications" && request.method === "GET") {
				return listNotifications(url, env);
			}

			return json({ ok: false, error: "Not found" }, 404);
		} catch (error) {
			return json({ ok: false, error: errorMessage(error) }, 500);
		}
	},

	async scheduled(_event: ScheduledController, env: AppEnv, ctx: ExecutionContext): Promise<void> {
		ctx.waitUntil(runNotificationChecks(env));
	},
} satisfies ExportedHandler<AppEnv>;

async function syncTrackedItems(request: Request, env: AppEnv): Promise<Response> {
	const body = (await request.json()) as SyncTrackedItemsRequest;
	const userID = cleanID(body.userID ?? body.userId);

	if (!userID) {
		return json({ ok: false, error: "Missing userID" }, 400);
	}

	const items = (body.items ?? [])
		.map(normalizeTrackedItem)
		.filter((item): item is Required<TrackedItemInput> & { tmdbID: number; title: string; kind: string; reason: string } => item !== null);

	const now = new Date().toISOString();

	await env.vestigo
		.prepare("INSERT OR IGNORE INTO users (id, created_at) VALUES (?, ?)")
		.bind(userID, now)
		.run();

	for (const item of items) {
		const trackedID = trackedItemID(userID, item.kind, item.tmdbID, item.reason);
		await env.vestigo
			.prepare(
				`INSERT INTO tracked_items
					(id, user_id, tmdb_id, kind, title, release_date, reason, created_at)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?)
				 ON CONFLICT(user_id, tmdb_id, kind, reason)
				 DO UPDATE SET
					title = excluded.title,
					release_date = excluded.release_date`
			)
			.bind(trackedID, userID, item.tmdbID, item.kind, item.title, item.releaseDate ?? null, item.reason, now)
			.run();
	}

	return json({ ok: true, synced: items.length });
}

async function listNotifications(url: URL, env: AppEnv): Promise<Response> {
	const userID = cleanID(url.searchParams.get("userID") ?? url.searchParams.get("userId"));

	if (!userID) {
		return json({ ok: false, error: "Missing userID" }, 400);
	}

	const result = await env.vestigo
		.prepare(
			`SELECT id, type, title, body, payload_json, created_at, sent_at
			 FROM notification_candidates
			 WHERE user_id = ?
			 ORDER BY created_at DESC
			 LIMIT 100`
		)
		.bind(userID)
		.all();

	return json({ ok: true, notifications: result.results ?? [] });
}

async function runNotificationChecks(env: AppEnv): Promise<void> {
	await createSavedItemReleasedCandidates(env);
}

async function createSavedItemReleasedCandidates(env: AppEnv): Promise<void> {
	const today = new Date().toISOString().slice(0, 10);
	const now = new Date().toISOString();
	const result = await env.vestigo
		.prepare(
			`SELECT id, user_id, tmdb_id, kind, title, release_date, reason
			 FROM tracked_items
			 WHERE release_date IS NOT NULL
			   AND release_date != ''
			   AND release_date <= ?
			   AND reason IN ('watchlist', 'upcoming', 'saved')`
		)
		.bind(today)
		.all<TrackedItemRow>();

	for (const item of result.results ?? []) {
		const notificationID = `${item.user_id}:${item.id}:saved_item_released`;
		const payload = {
			tmdbID: item.tmdb_id,
			kind: item.kind,
			trackedItemID: item.id,
			releaseDate: item.release_date,
		};

		await env.vestigo
			.prepare(
				`INSERT OR IGNORE INTO notification_candidates
					(id, user_id, tracked_item_id, type, title, body, payload_json, created_at)
				 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
			)
			.bind(
				notificationID,
				item.user_id,
				item.id,
				"saved_item_released",
				`${item.title} is out now`,
				`${item.title} has been released.`,
				JSON.stringify(payload),
				now
			)
			.run();

		await env.vestigo
			.prepare("UPDATE tracked_items SET last_checked_at = ? WHERE id = ?")
			.bind(now, item.id)
			.run();
	}
}

function normalizeTrackedItem(input: TrackedItemInput): (Required<TrackedItemInput> & { tmdbID: number; title: string; kind: string; reason: string }) | null {
	const tmdbID = input.tmdbID ?? input.tmdbId;
	const title = input.title?.trim();
	const kind = normalizeKind(input.kind);
	const reason = normalizeReason(input.reason);

	if (!tmdbID || !title || !kind || !reason) {
		return null;
	}

	return {
		...input,
		tmdbID,
		title,
		kind,
		reason,
		releaseDate: input.releaseDate ?? null,
	};
}

function normalizeKind(value: string | undefined): string | null {
	if (value === "movie" || value === "tv") {
		return value;
	}

	return null;
}

function normalizeReason(value: string | undefined): string {
	const cleaned = value?.trim() || "watchlist";
	return cleaned.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 40);
}

function trackedItemID(userID: string, kind: string, tmdbID: number, reason: string): string {
	return `${userID}:${kind}:${tmdbID}:${reason}`;
}

function cleanID(value: string | null | undefined): string | null {
	const cleaned = value?.trim();
	if (!cleaned) {
		return null;
	}

	return cleaned.slice(0, 128);
}

function json(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: jsonHeaders,
	});
}

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : "Unknown error";
}
