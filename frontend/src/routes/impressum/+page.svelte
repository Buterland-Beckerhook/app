<script lang="ts">
	let { data } = $props();
</script>

<svelte:head>
	<title>Impressum &mdash; Schützenverein Buterland-Beckerhook</title>
</svelte:head>

<h1 class="mb-8 text-3xl font-bold">Impressum</h1>

{#if data.page?.body}
	<div class="prose dark:prose-invert max-w-none">
		{@html data.page.body}
	</div>
{/if}
