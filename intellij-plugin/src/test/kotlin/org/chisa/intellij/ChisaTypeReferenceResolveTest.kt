package org.chisa.intellij

import com.intellij.psi.util.PsiTreeUtil
import com.intellij.testFramework.fixtures.BasePlatformTestCase
import org.chisa.intellij.psi.ChisaStructDeclaration
import org.chisa.intellij.psi.ChisaTypeReferenceElement

class ChisaTypeReferenceResolveTest : BasePlatformTestCase() {

    override fun getTestDataPath(): String = "src/test/resources"

    fun testTypeReferenceResolvesToStruct() {
        val file = myFixture.configureByText(
            "test.chisa",
            """
            struct Point { }
            let p: Point = 0;
            """.trimIndent()
        )

        val typeRef = PsiTreeUtil.findChildOfType(file, ChisaTypeReferenceElement::class.java)
        assertNotNull("TYPE_REFERENCE element should exist", typeRef)

        val ref = typeRef!!.reference
        assertNotNull("TYPE_REFERENCE should have a reference", ref)

        val resolved = ref!!.resolve()
        assertNotNull("Reference should resolve to a declaration", resolved)
        assertInstanceOf(resolved, ChisaStructDeclaration::class.java)
        assertEquals("Point", (resolved as ChisaStructDeclaration).name)
    }

    fun testTypeReferenceForwardResolvesToStruct() {
        val file = myFixture.configureByText(
            "test.chisa",
            """
            let p: MyStruct = 0;
            struct MyStruct { }
            """.trimIndent()
        )

        val typeRef = PsiTreeUtil.findChildOfType(file, ChisaTypeReferenceElement::class.java)
        assertNotNull("TYPE_REFERENCE element should exist", typeRef)

        val resolved = typeRef!!.reference?.resolve()
        assertNotNull("Forward reference should resolve", resolved)
        assertInstanceOf(resolved, ChisaStructDeclaration::class.java)
        assertEquals("MyStruct", (resolved as ChisaStructDeclaration).name)
    }

    fun testImportedTypeReferenceResolvesToStruct() {
        myFixture.addFileToProject(
            "types.chisa",
            """
            struct MyStruct { }
            """.trimIndent()
        )
        val file = myFixture.configureByText(
            "main.chisa",
            """
            import { MyStruct } from "./types.chisa";
            let x: MyStruct = 0;
            """.trimIndent()
        )

        val typeRefs = PsiTreeUtil.findChildrenOfType(file, ChisaTypeReferenceElement::class.java)
        val myStructRef = typeRefs.find { it.getReferenceName() == "MyStruct" }
        assertNotNull("Should find type reference to MyStruct", myStructRef)

        val resolved = myStructRef!!.reference?.resolve()
        assertNotNull("Imported type reference should resolve", resolved)
        assertInstanceOf(resolved, ChisaStructDeclaration::class.java)
        assertEquals("MyStruct", (resolved as ChisaStructDeclaration).name)
    }

    fun testTypeReferenceUnresolved() {
        val file = myFixture.configureByText(
            "test.chisa",
            """
            let p: Unknown = 0;
            """.trimIndent()
        )

        val typeRef = PsiTreeUtil.findChildOfType(file, ChisaTypeReferenceElement::class.java)
        assertNotNull("TYPE_REFERENCE element should exist", typeRef)

        val resolved = typeRef!!.reference?.resolve()
        assertNull("Reference to undefined type should not resolve", resolved)
    }
}
