<script lang="ts">
	import type { Person } from '$lib/types';

	let { people, title }: { people: Person[]; title: string } = $props();
</script>

<section>
	<h2 class="mb-4 text-xl font-semibold">{title}</h2>
	<div class="overflow-x-auto">
		<table class="w-full text-left text-sm">
			<thead>
				<tr class="border-b-2 border-gray-200">
					<th class="py-2 pr-4 font-medium text-gray-500">Amt</th>
					<th class="py-2 font-medium text-gray-500">Name</th>
				</tr>
			</thead>
			<tbody>
				{#each people as person (person.id)}
					<tr class="border-b border-gray-100">
						<td class="py-2 pr-4 font-medium">{person.role}</td>
						<td class="py-2">{person.name}</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
</section>
