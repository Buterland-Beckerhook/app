<script lang="ts">
	import Breadcrumb from '$lib/components/Breadcrumb.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>Datenschutzerklärung &mdash; Schützenverein Buterland-Beckerhook</title>
</svelte:head>

<Breadcrumb crumbs={[{ label: 'Datenschutz' }]} />

<h1 class="mb-8 text-3xl font-bold">Datenschutzerklärung</h1>

{#if data.page?.body}
	<div class="prose dark:prose-invert max-w-none">
		{@html data.page.body}
	</div>
{/if}
