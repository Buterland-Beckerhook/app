<script lang="ts">
	import Breadcrumb from '$lib/components/Breadcrumb.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>Verein &mdash; Schützenverein Buterland-Beckerhook</title>
	<meta
		name="description"
		content="Informationen über den Schützenverein Buterland-Beckerhook e.V. - Vorstand, Offiziere und mehr."
	/>
</svelte:head>

<Breadcrumb crumbs={[{ label: 'Verein' }]} />

<h1 class="mb-8 text-3xl font-bold">Unser Verein</h1>

{#if data.page?.body}
	<div class="prose dark:prose-invert mb-8 max-w-none">
		{@html data.page.body}
	</div>
{/if}

{#if data.subPages.length > 0}
	<nav class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
		{#each data.subPages as subPage (subPage.id)}
			<a
				href="/verein/{subPage.slug}"
				class="group rounded-lg border border-gray-200 p-5 transition-colors hover:border-primary/50 hover:bg-gray-50 dark:border-zinc-700 dark:hover:border-primary/50 dark:hover:bg-zinc-800"
			>
				<h2
					class="text-lg font-semibold text-gray-900 group-hover:text-primary dark:text-gray-100 dark:group-hover:text-primary"
				>
					{subPage.title}
				</h2>
			</a>
		{/each}
	</nav>
{/if}
