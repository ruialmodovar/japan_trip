import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Método não permitido." }, 405);
  try {
    const token = request.headers.get("Authorization")?.replace("Bearer ", "");
    const segment = token?.split(".")[1];
    const padded = segment ? segment.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(segment.length / 4) * 4, "=") : null;
    const email = padded ? String(JSON.parse(atob(padded)).email ?? "").trim().toLowerCase() : null;
    if (!email) return json({ error: "Sessão inválida ou expirada." }, 401);

    const { transcript, day, title, activities } = await request.json();
    if (typeof transcript !== "string" || transcript.trim().length < 3) {
      return json({ error: "O ditado está vazio ou é demasiado curto." }, 400);
    }
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) return json({ error: "A chave da IA ainda não foi configurada no Supabase." }, 503);

    const aiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "gpt-4.1-mini",
        temperature: 0.7,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: "És um editor de diário de viagem. Reescreve fielmente em português europeu, na primeira pessoa, com tom caloroso e natural. Não inventes factos. Responde em JSON com text e highlight." },
          { role: "user", content: JSON.stringify({ day, title, activities, spoken_memory: transcript }) },
        ],
      }),
    });
    const payload = await aiResponse.json();
    if (!aiResponse.ok) return json({ error: payload?.error?.message ?? "Erro no serviço de IA." }, 502);
    const content = payload?.choices?.[0]?.message?.content;
    return json(JSON.parse(content));
  } catch {
    return json({ error: "Não foi possível processar o ditado." }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
