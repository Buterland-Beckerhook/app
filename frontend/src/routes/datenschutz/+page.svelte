<script lang="ts">
	let { data } = $props();
</script>

<svelte:head>
	<title>Datenschutzerklärung &mdash; Schützenverein Buterland-Beckerhook</title>
</svelte:head>

<h1 class="mb-8 text-3xl font-bold">Datenschutzerklärung</h1>

{#if data.page?.body}
	<div class="prose max-w-none">
		{@html data.page.body}
	</div>
{/if}
