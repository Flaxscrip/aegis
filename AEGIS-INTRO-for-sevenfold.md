# Aegis intro for Sevenfold

**From:** Aegis (the egress-isolated deployment of Hearthold on Archon)
**To:** the Sevenfold Dev AI (`~/Projects/Sevenfold`, repo `flaxscrip/Sevenfold`)
**Purpose:** introduce Sevenfold to the isolated substrate it will run on, establish the
layering/boundaries, and set a first orientation deliverable.

---

You've been building Sevenfold as a card-game interface over Hearthold — every vault
artefact/VC is a Card. This introduces the layer *underneath* Hearthold that Sevenfold will
actually run on: **Aegis**.

## What Aegis is
Aegis (`~/isolation/aegis`, repo `flaxscrip/aegis`) is the **egress-isolated, fully-offline
deployment of Hearthold on Archon**. It runs the whole stack — Archon gatekeeper/keymaster,
Hearthold agents — on `internal: true` Docker networks with **zero public internet access**,
proven (every container `ENETUNREACH` to the outside). Two Aegis nodes on the **same LAN**
can peer point-to-point (private DIDComm, on-demand DID resolution) with no cloud, no central
server, no accounts. It's the air-gapped, privacy-first substrate: a person's data lives
entirely on their own machine.

## The layering (know your lane)
Sevenfold (UI: **Cards** & **Tables**) → Hearthold (**verifiable credentials** & agents) →
Archon (DIDs/keymaster) → **Aegis** (the isolated deployment it all runs in).

Sevenfold owns the game metaphor and talks to **Hearthold's API**. It must **not** reach into
Aegis containers, Docker, or Archon internals, and must not reimplement DID/credential logic.
Keep "Card"/"Table" as *Sevenfold's* vocabulary only — Hearthold says "credential," Aegis says
"isolated node."

## How the metaphor maps down
- A **Table** ≈ a player's Sovereign identity on their own Aegis node.
- **Passing a Card from one Table to another** ≈ Hearthold delivering a verifiable credential
  over DIDComm from one Aegis node to another **on the same local network**.

Hearthold is building exactly this cross-node credential-delivery primitive now (see
`~/isolation/aegis/HEARTHOLD-ASK-cross-node-credential-delivery.md`), so your P2P card-passing
will land *through* Hearthold, on the Aegis peer link. You don't build the transport; you
drive it.

## What running on Aegis requires of you — headline constraint: fully self-contained / offline-first
Aegis is air-gapped, so at runtime Sevenfold can make **no external network calls whatsoever**
— no CDNs, no Google/remote fonts, no analytics/telemetry, no cloud APIs, no external image or
asset hosts. Everything must be bundled, inlined, or served locally. Likewise there's **no
cloud, no central server, no accounts**: two players are two nodes on a LAN; design for
offline-first, local discovery, and graceful connect/disconnect.

## First deliverable (orientation, no big build yet)
1. Read for understanding (do **not** modify): `~/isolation/aegis/SANDBOX-PROFILE.md` (the
   isolation) and `~/isolation/aegis/deploy/two-node/README.md` (the two-node peer model + how
   a credential crosses between nodes). Confirm back your understanding of the layering and the
   Table↔node / Card↔credential mapping.
2. **Audit `apps/table` (Vite/React) and `packages/cardstock` for anything that would break
   air-gapped** — external fonts, CDN scripts/styles, remote images, fetch/XHR/WebSocket to
   non-local hosts, analytics, telemetry, cloud SDKs. Report every finding; propose making each
   one self-contained. This is the concrete gate to "Sevenfold can run inside the sandbox."
3. Sketch (don't implement) how "pass a Card between two Tables" maps onto the Aegis two-node
   model — which player action triggers a Hearthold credential delivery, and what the UI shows
   on send/receive/accept.

## Boundary
If you need something from the Aegis substrate (a network wire, an env flag, an endpoint),
don't touch Aegis — route the request back through the operator to the Aegis builder.
