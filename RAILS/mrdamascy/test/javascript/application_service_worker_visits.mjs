const visits = listeners["turbo:load"] || []
visits.forEach((handler) => { handler(); handler() })
console.log(JSON.stringify({ registered }))
