# AI Jarvis V2 需求资料索引

本目录保存 V2 正式基线、候选验收、任务资料和历史参考。本文只做导航，不新增需求；正式任务按命中范围读取，禁止批量加载。当前基线身份和 SHA-256 以 [`baseline-manifest.md`](baseline-manifest.md) 为唯一来源；其他文件中的哈希仅代表其创建时记录，不用于判断当前基线。

## 正式基线、编号与范围

[baseline-manifest.md](baseline-manifest.md) · [requirements-catalog.md](requirements-catalog.md) · [traceability-matrix.md](traceability-matrix.md) · [scope-exclusions.md](scope-exclusions.md) · [nfr-classification-and-traceability.md](nfr-classification-and-traceability.md)

## 候选验收与阶段记录

[acceptance-baseline-v1.0.md](acceptance-baseline-v1.0.md) · [nfr-engineering-appendix-manifest-v1.0.md](nfr-engineering-appendix-manifest-v1.0.md) · [nfr-stage-gate-review.md](nfr-stage-gate-review.md) · [calibration-register.md](calibration-register.md) · [nfr-open-risks-and-pending-validation.md](nfr-open-risks-and-pending-validation.md)

## 度量、校准与开放项

[nfr-metrics-framework.md](nfr-metrics-framework.md) · [nfr-measurement-points.md](nfr-measurement-points.md) · [update-observability-fields.md](update-observability-fields.md)

## 性能、可靠性与恢复

[performance-nfr.md](performance-nfr.md) · [performance-benchmark-scenarios.md](performance-benchmark-scenarios.md) · [performance-record-templates.md](performance-record-templates.md) · [reliability-nfr.md](reliability-nfr.md) · [reliability-fault-recovery-matrix.md](reliability-fault-recovery-matrix.md) · [reliability-test-and-record-templates.md](reliability-test-and-record-templates.md)

## 隐私、数据、安装与更新

[privacy-security-nfr.md](privacy-security-nfr.md) · [threat-boundaries-and-network-behavior.md](threat-boundaries-and-network-behavior.md) · [data-residency-and-clearing-matrix.md](data-residency-and-clearing-matrix.md) · [diagnostic-package-minimization.md](diagnostic-package-minimization.md) · [privacy-security-validation-record-templates.md](privacy-security-validation-record-templates.md) · [offline-install-update-nfr.md](offline-install-update-nfr.md) · [offline-install-update-validation-plan.md](offline-install-update-validation-plan.md) · [package-layout-and-version-compatibility.md](package-layout-and-version-compatibility.md) · [dependency-governance-sbom-and-replacement-strategy.md](dependency-governance-sbom-and-replacement-strategy.md)

## Windows 与 Overlay

[windows-compatibility-nfr.md](windows-compatibility-nfr.md) · [windows-hardware-acceptance-matrix.md](windows-hardware-acceptance-matrix.md) · [windows-display-capture-matrix.md](windows-display-capture-matrix.md) · [windows-validation-record-templates.md](windows-validation-record-templates.md) · [windows-device-overlay-scenarios.md](windows-device-overlay-scenarios.md)

## O/V、后处理、回放与验收

[O_MODEL_CAPABILITY_VALIDATION_MATRIX.md](O_MODEL_CAPABILITY_VALIDATION_MATRIX.md) · [o-model-runtime-candidate-screening.md](o-model-runtime-candidate-screening.md) · [o-mode-acceptance-and-benchmark-plan.md](o-mode-acceptance-and-benchmark-plan.md) · [o-duplex-autonomous-text-poc.md](o-duplex-autonomous-text-poc.md) · [v-model-runtime-candidate-screening.md](v-model-runtime-candidate-screening.md) · [v-model-runtime-candidate-lock.json](v-model-runtime-candidate-lock.json) · [v-mode-acceptance-and-benchmark-plan.md](v-mode-acceptance-and-benchmark-plan.md) · [v-multimage-poc-audit.md](v-multimage-poc-audit.md) · [postprocessing-overlay-lifecycle-acceptance-plan.md](postprocessing-overlay-lifecycle-acceptance-plan.md) · [replay-corpus-and-gold-format.md](replay-corpus-and-gold-format.md) · [e2e-acceptance-matrix.md](e2e-acceptance-matrix.md)

## V1 资产与依赖参考

[v1-open-source-asset-reuse-final-audit.md](v1-open-source-asset-reuse-final-audit.md) · [v1-runtime-model-third-party-license-audit.md](v1-runtime-model-third-party-license-audit.md) · [v1-source-reuse-matrix.md](v1-source-reuse-matrix.md) · [v1-source-snapshot-and-asset-inventory.md](v1-source-snapshot-and-asset-inventory.md) · [v1-ui-resource-config-test-reuse-matrix.md](v1-ui-resource-config-test-reuse-matrix.md)

`templates/` 仅存记录模板；只有当前任务明确命中时读取。新增需求、冻结变更和跨任务决定分别遵循 `AGENTS.md`、`DECISIONS.md` 与 Dashi 流程。
