<script lang="ts">
	interface Crumb {
		label: string;
		href?: string;
	}

	let { crumbs }: { crumbs: Crumb[] } = $props();
</script>

<nav aria-label="Breadcrumb" class="mb-6 hidden text-sm text-gray-500 dark:text-gray-400 md:block">
	<ol class="flex items-center gap-1.5">
		<li>
			<a href="/" class="transition-colors hover:text-primary">Startseite</a>
		</li>
		{#each crumbs as crumb, i (crumb.label)}
			<li class="flex items-center gap-1.5">
				<span aria-hidden="true">/</span>
				{#if crumb.href && i < crumbs.length - 1}
					<a href={crumb.href} class="transition-colors hover:text-primary">{crumb.label}</a>
				{:else}
					<span class="text-gray-900 dark:text-gray-100">{crumb.label}</span>
				{/if}
			</li>
		{/each}
	</ol>
</nav>
