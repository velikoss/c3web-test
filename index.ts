Bun.serve({
    port: 8080,
    async fetch(req) {
        return new Response(Bun.file("./web/index.html"));
    },
});