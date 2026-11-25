//
//  WebClientPage.swift
//  FunnyPlanner
//
//  Página única (HTML/CSS/JS) servida ao navegador dos participantes. Conecta no
//  WebSocket `/ws`, mostra o baralho, envia votos e re-renderiza ao receber o estado.
//  Sem dependências externas — tudo inline.
//

nonisolated enum WebClientPage {
    static let html = """
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>FunnyPlanner</title>
    <style>
      :root { color-scheme: light dark; }
      * { box-sizing: border-box; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        margin: 0; padding: 24px; max-width: 720px; margin-inline: auto;
      }
      h1 { font-size: 1.4rem; margin: 0 0 4px; }
      .me { color: #888; font-size: .9rem; margin-bottom: 20px; }
      .deck { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 28px; }
      .card {
        flex: 0 0 auto; width: 64px; height: 92px; border-radius: 12px;
        border: 2px solid #c9c9c9; background: transparent; cursor: pointer;
        font-size: 1.3rem; font-weight: 600; transition: transform .08s, border-color .1s;
      }
      .card:hover { transform: translateY(-4px); }
      .card.selected { border-color: #0a84ff; background: #0a84ff; color: white; }
      .status { font-size: 1rem; margin-bottom: 12px; opacity: .8; }
      ul { list-style: none; padding: 0; margin: 0; }
      li {
        display: flex; justify-content: space-between; align-items: center;
        padding: 10px 14px; border-radius: 10px; background: rgba(128,128,128,.12);
        margin-bottom: 8px;
      }
      .badge { font-weight: 600; }
      .voted { color: #30d158; }
      .waiting { color: #ff9f0a; }
      .vote-value {
        min-width: 34px; text-align: center; font-weight: 700;
        background: rgba(10,132,255,.15); border-radius: 8px; padding: 2px 8px;
      }
      .closed { text-align: center; padding: 60px 0; opacity: .7; }
    </style>
    </head>
    <body>
      <h1>🃏 FunnyPlanner</h1>
      <div class="me" id="me"></div>
      <div id="app">
        <div class="deck" id="deck"></div>
        <div class="status" id="status"></div>
        <ul id="participants"></ul>
      </div>

    <script>
      let myId = null;
      let myVote = null;
      let ws = null;

      function connect() {
        // Usa wss:// quando a página é servida por HTTPS (atrás de túnel/proxy TLS),
        // senão ws:// na rede local. Evita bloqueio de mixed content no navegador.
        const proto = location.protocol === "https:" ? "wss://" : "ws://";
        ws = new WebSocket(proto + location.host + "/ws");
        ws.onmessage = (event) => {
          const msg = JSON.parse(event.data);
          if (msg.type === "welcome") {
            myId = msg.id;
            document.getElementById("me").textContent = "Você entrou como " + msg.name;
          } else if (msg.type === "state") {
            render(msg);
          }
        };
        ws.onclose = () => {
          document.getElementById("app").innerHTML =
            '<div class="closed">A sala foi encerrada. 👋</div>';
        };
      }

      function vote(value) {
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: "vote", value: value }));
        }
      }

      function render(state) {
        const revealed = state.phase === "revealed";

        // Baralho — só na fase de votação.
        const deck = document.getElementById("deck");
        const me = state.participants.find(p => p.id === myId);
        myVote = me ? me.vote : null;
        deck.style.display = revealed ? "none" : "flex";
        deck.innerHTML = "";
        state.cards.forEach(card => {
          const btn = document.createElement("button");
          btn.className = "card" + (!revealed && myVote === card ? " selected" : "");
          btn.textContent = card;
          btn.onclick = () => vote(card);
          deck.appendChild(btn);
        });

        // Status.
        const voted = state.participants.filter(p => p.hasVoted).length;
        document.getElementById("status").textContent = revealed
          ? "Votos revelados"
          : "Votaram " + voted + " de " + state.participants.length;

        // Lista de participantes.
        const list = document.getElementById("participants");
        list.innerHTML = "";
        state.participants.forEach(p => {
          const li = document.createElement("li");
          const name = document.createElement("span");
          name.textContent = p.name + (p.id === myId ? " (você)" : "");
          const badge = document.createElement("span");
          if (revealed) {
            badge.className = "vote-value";
            badge.textContent = p.vote != null ? p.vote : "—";
          } else {
            badge.className = "badge " + (p.hasVoted ? "voted" : "waiting");
            badge.textContent = p.hasVoted ? "✓ votou" : "aguardando";
          }
          li.appendChild(name);
          li.appendChild(badge);
          list.appendChild(li);
        });
      }

      connect();
    </script>
    </body>
    </html>
    """
}
