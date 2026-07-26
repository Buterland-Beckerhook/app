# Memory Index

- [Public-site redesign](project_public_site_redesign.md) — design-handoff restyle scope: admin/core_components deliberately untouched; primary vs accent token semantics
- [Strict CSP, no inline handlers](project_strict_csp_no_inline_handlers.md) — prod CSP blocks inline on* handlers; dev has CSP off and the suite runs no JS, so both pass silently — flag any onclick= in templates
- [LiveView hook payload trust](project_liveview_hook_payload_trust.md) — ids from pushEvent are browser input; non-UUIDs raise CastError on reads and ChangeError on writes, killing the LiveView
- [Ordering.renumber deadlock shape](project_ordering_renumber_deadlock_shape.md) — row-by-row position rewrites deadlock on concurrent reorders; pairwise FOR UPDATE does not help
