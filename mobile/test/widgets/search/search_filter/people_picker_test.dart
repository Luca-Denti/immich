import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/person.model.dart';
import 'package:immich_mobile/providers/infrastructure/people.provider.dart';
import 'package:immich_mobile/widgets/search/search_filter/people_picker.dart';

import '../../../unit/presentation/presentation_context.dart';

void main() {
  testWidgets('selecting a person does not mutate the committed filter', (tester) async {
    const person = Person(id: 'person-1', name: 'Alice');
    final committedFilter = <Person>{};
    Set<Person>? selectedPeople;
    final presentationContext = await PresentationContext.create();
    addTearDown(presentationContext.dispose);

    await tester.pumpTestWidget(
      presentationContext,
      PeoplePicker(filter: committedFilter, onSelect: (value) => selectedPeople = value),
      overrides: [
        getAllPeopleProvider.overrideWith((ref) => Stream.value([person])),
      ],
    );

    await tester.tap(find.text('Alice'));
    await tester.pump();

    expect(selectedPeople, contains(person));
    expect(committedFilter, isEmpty);
  });
}
