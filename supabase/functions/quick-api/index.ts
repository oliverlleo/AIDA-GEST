// Retain the existing endpoint with the same upload contract and authorization.
import { createHandler } from '../upload-workspace-logo/handler.mjs';
Deno.serve(createHandler((name: string) => Deno.env.get(name)));
