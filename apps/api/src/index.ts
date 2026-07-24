import { createAiQueue } from "./ai/queue.js";
import { config } from "./config.js";
import { MemoryStore } from "./memory-store.js";
import { createObjectStore } from "./object-store.js";
import { PgStore } from "./pg-store.js";
import { createServer } from "./server.js";

const store = config.DATABASE_URL ? new PgStore(config.DATABASE_URL) : new MemoryStore();
const app = await createServer({ config, store, objects: createObjectStore(config), aiQueue: await createAiQueue(config.REDIS_URL) });
if (store instanceof PgStore) app.addHook("onClose", async () => store.close());
await app.listen({ host: config.HOST, port: config.PORT });
