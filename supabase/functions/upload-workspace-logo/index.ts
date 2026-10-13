import { createHandler } from './handler.mjs';
Deno.serve(createHandler((name: string) => Deno.env.get(name)));
