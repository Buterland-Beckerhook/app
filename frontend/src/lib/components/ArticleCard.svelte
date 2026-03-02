<script lang="ts">
	import type { Article } from '$lib/types';
	import { getFirstImage, getImageUrl, getImageAlt } from '$lib/utils/image';
	import DateFormat from './DateFormat.svelte';

	let { article }: { article: Article } = $props();

	let thumbnail = $derived(getFirstImage(article.images));
	let year = $derived(new Date(article.date_published).getFullYear());
</script>

<article class="border-b border-gray-200 py-6 last:border-b-0 dark:border-zinc-700">
	<a href="/aktuell/{year}/{article.slug}" class="group block">
		<div class="flex gap-4">
			{#if thumbnail}
				<div class="hidden shrink-0 sm:block">
					<img
						src={getImageUrl(thumbnail, 320, 213)}
						alt={getImageAlt(thumbnail)}
						width="320"
						height="213"
						loading="lazy"
						class="h-auto w-40 rounded-lg object-cover md:w-52"
					/>
				</div>
			{/if}
			<div class="flex min-w-0 flex-col gap-2">
				<time datetime={article.date_published} class="text-sm text-gray-500 dark:text-gray-400">
					<DateFormat date={article.date_published} />
				</time>
				<h2 class="text-xl font-semibold group-hover:text-primary">
					{article.title}
				</h2>
				{#if article.subtitle}
					<p class="text-gray-600 dark:text-gray-300">{article.subtitle}</p>
				{/if}
				{#if article.tags && article.tags.length > 0}
					<div class="flex flex-wrap gap-2">
						{#each article.tags as tag (tag)}
							<span
								class="rounded-full bg-primary/10 px-3 py-0.5 text-xs text-primary dark:bg-primary/20"
								>{tag}</span
							>
						{/each}
					</div>
				{/if}
			</div>
		</div>
	</a>
</article>
