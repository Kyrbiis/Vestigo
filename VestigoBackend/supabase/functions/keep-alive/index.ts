Deno.serve(async () => {
  await fetch("https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api/health")
    .catch(() => {})
  return new Response("ok")
})
