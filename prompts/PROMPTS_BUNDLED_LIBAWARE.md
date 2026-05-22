# PB' (Bundled, library-aware variant) — *Sanitized for external release*

> The verbatim text of PB' is withheld at the request of institutional
> review because it includes verbatim attribute-tag identifiers from a
> vendor pad-cell metadata file. The information below preserves the
> structure of the prompt and the methodological lesson without
> disclosing proprietary tag identifiers.

## Origin

Bundled-prompt variant tested with the two API-condition Claude models
(Opus 4.7 and Opus 4.6) — three trials each, six trials total.

## Structure (paraphrased)

PB' is identical to PB except that it adds a "library contract"
section instructing the LLM to use four specific identifiers as the
externally-visible port names of the `pad_input` and `pad_output`
modules. Those identifiers were paraphrased verbatim from a vendor
pad-cell metadata file the authors had been reading at the time.

## Outcome

All six PB' responses adopted the mandated identifier names but
failed Tessent ELAB 6/6 with a port-binding error: the identifiers
do not exist as Verilog ports on the toolchain-synthesized pad-cell
stub. The metadata file uses those identifiers as **attribute tags**
on ports whose actual Verilog names differ.

## Why released as an artifact

PB' is the negative half of a worked example of author-side prompt
contamination: we read attribute tags as port names, mandated a
contract the stub rejects, and the LLM followed us off the cliff.
PB'' (next file) recovers 6/6 by rebuilding the contract from the
synthesized stub. We release PB'/PB'' as a structural illustration
without the proprietary identifiers.
