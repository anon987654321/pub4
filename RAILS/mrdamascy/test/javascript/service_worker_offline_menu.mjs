await new Promise((resolve) => handlers.install({ waitUntil: (work) => work.then(resolve) }))
const seen = { online: await navigate("/") }
network.online = false
seen.menu = await navigate("/")
seen.loyalty = await navigate("/loyalty")
console.log(JSON.stringify(seen))
