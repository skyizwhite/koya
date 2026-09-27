# A webhook to an internal address is sent, and its answer is not kept

*2026-09-28*

## Context

Webhook URLs come from the schema, which a management key deploys, and each
call's answer is kept in the delivery log for the owner to read. Unchecked,
the holder of a management key could have the server request a cloud's
metadata address or a service on its own network and read the answer there.
Refusing every internal address would also refuse the common case of a site's
container beside the server, or a site on localhost while developing.

## Decision

- A webhook URL starts with `http://` or `https://`.
- Before each call the host is resolved. If any of its addresses is link-local,
  multicast, unspecified or reserved, or a cloud's metadata address outside
  those ranges, nothing is sent. An IPv4 address carried in IPv6 is judged as
  itself.
- If any is loopback or private, the call is sent and only its status is kept.
- Only an answer from a host whose addresses are all public keeps its body.
- A plain `http` call connects to the address that was checked, and names the
  host in `Host`. An `https` call connects by name, which its certificate needs.

## Consequences

- An internal answer cannot be read through the delivery log, and a metadata
  address cannot be reached at all.
- A receiver beside the server works as before; its error message is not in
  the log, and is read in the receiver's own logs.
- The server can still be made to POST to an internal address it could reach
  anyway, without seeing the answer.
- An `https` call resolves the name again when it connects, so a name that
  changes its answer in between can reach an internal `https` service and have
  its answer kept. A metadata address answers plain `http` only, which never
  resolves twice.
