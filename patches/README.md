# Patches to vendored upstream source

`rticonnextdds-gateway/` itself is not committed to this repo (see the root
[README.md](../README.md#upstream-baseline) for the pinned clone/checkout
commands). This directory holds diffs for local fixes applied on top of that
pinned commit, to be reapplied after cloning/checking out the gateway.

## DdsToProtobuf.cpp.patch

Fixes a benign but noisy `DDS_DynamicData2_get_string: Output buffer too
small` ERROR log emitted by the Protobuf transformation plugin. Root cause:
`ProtobufConverterState::str_buffer` was being shrunk to the exact length of
every converted string, discarding its high-water mark and causing repeated
undersized-buffer retries (each logged as an ERROR) whenever a
subsequently-converted string was longer than the immediately preceding one.

Applies to `common/protobuf2dds/srcCxx/DdsToProtobuf.cpp` at commit
`a9e68fbdf5a6b32dc766eb1f38b41ba9fdbe4d0d`.

To apply, from the `rticonnextdds-gateway` directory:

```powershell
git apply "..\patches\DdsToProtobuf.cpp.patch"
```

Then rebuild and reinstall the `rtiprotobuftransf` target per the root
README's Build plan.
