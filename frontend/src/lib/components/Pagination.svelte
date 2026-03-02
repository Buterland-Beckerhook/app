<script lang="ts">
	let {
		currentPage,
		totalPages,
		baseUrl
	}: { currentPage: number; totalPages: number; baseUrl: string } = $props();

	let pages = $derived(Array.from({ length: totalPages }, (_, i) => i + 1));
</script>

{#if totalPages > 1}
	<nav aria-label="Seitennavigation" class="flex items-center justify-center gap-2 py-8">
		{#if currentPage > 1}
			<a
				href="{baseUrl}?seite={currentPage - 1}"
				class="rounded border border-gray-300 px-3 py-2 text-sm hover:bg-gray-50 dark:border-gray-600 dark:hover:bg-gray-700"
				aria-label="Vorherige Seite"
			>
				&larr;
			</a>
		{/if}

		{#each pages as page (page)}
			{#if page === currentPage}
				<span
					class="rounded bg-primary px-3 py-2 text-sm font-medium text-white"
					aria-current="page"
				>
					{page}
				</span>
			{:else}
				<a
					href="{baseUrl}?seite={page}"
					class="rounded border border-gray-300 px-3 py-2 text-sm hover:bg-gray-50 dark:border-gray-600 dark:hover:bg-gray-700"
				>
					{page}
				</a>
			{/if}
		{/each}

		{#if currentPage < totalPages}
			<a
				href="{baseUrl}?seite={currentPage + 1}"
				class="rounded border border-gray-300 px-3 py-2 text-sm hover:bg-gray-50 dark:border-gray-600 dark:hover:bg-gray-700"
				aria-label="Nächste Seite"
			>
				&rarr;
			</a>
		{/if}
	</nav>
{/if}
